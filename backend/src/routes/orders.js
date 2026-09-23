const { Router } = require('express');
const pool = require('../../db');
const messages = require('../constants/messages');
const { authenticateToken } = require('../middleware/auth');
const asyncHandler = require('../utils/asyncHandler');

const router = Router();

// 「进行中」标签同时展示服务进行中和中断待确认的订单
const STATUS_GROUPS = {
  in_progress: ['in_progress', 'pending_confirm'],
};

const findOrder = async (orderId) => {
  const [orders] = await pool.query(
    `SELECT o.*, n.expected_time AS need_expected_time
     FROM orders o
     LEFT JOIN needs n ON o.need_id = n.id
     WHERE o.id = ?`,
    [orderId],
  );
  return orders[0] || null;
};

router.get('/', authenticateToken, asyncHandler(async (req, res) => {
  const { status } = req.query;
  let sql = `SELECT o.*, n.title, n.type, n.address, n.expected_time,
    u1.name as user_name, u2.name as volunteer_name,
    e.id as exception_id, e.reason as exception_reason,
    e.expected_resume_time as exception_expected_time,
    e.reporter_id as exception_reporter_id, e.created_at as exception_created_at
    FROM orders o
    LEFT JOIN needs n ON o.need_id = n.id
    LEFT JOIN users u1 ON o.user_id = u1.id
    LEFT JOIN users u2 ON o.volunteer_id = u2.id
    LEFT JOIN order_exceptions e ON e.order_id = o.id AND e.status = 'pending'
    WHERE o.user_id = ? OR o.volunteer_id = ?`;
  const params = [req.user.id, req.user.id];

  if (status) {
    const group = STATUS_GROUPS[status] || [status];
    sql += ` AND o.status IN (${group.map(() => '?').join(', ')})`;
    params.push(...group);
  }

  sql += ' ORDER BY o.created_at DESC';

  const [rows] = await pool.query(sql, params);
  res.json({ orders: rows });
}));

router.put('/:id/complete', authenticateToken, asyncHandler(async (req, res) => {
  const { service_hours } = req.body;
  const orderId = req.params.id;
  const order = await findOrder(orderId);

  if (!order) {
    return res.status(404).json({ message: messages.orders.notFound });
  }

  if (order.user_id !== req.user.id && order.volunteer_id !== req.user.id) {
    return res.status(403).json({ message: messages.orders.forbidden });
  }

  if (order.status === 'pending_confirm') {
    return res.status(400).json({ message: messages.orders.completeBlocked });
  }

  if (order.status !== 'in_progress') {
    return res.status(400).json({ message: messages.orders.notInProgress });
  }

  await pool.query(
    "UPDATE orders SET status = 'completed', service_hours = ? WHERE id = ?",
    [service_hours || 1, orderId],
  );

  await pool.query(
    "UPDATE needs SET status = 'completed' WHERE id = ?",
    [order.need_id],
  );

  const hours = service_hours || 1;
  await pool.query(
    'UPDATE users SET service_hours = service_hours + ?, points = points + ? WHERE id = ?',
    [hours, hours * 10, order.volunteer_id],
  );

  res.json({ message: messages.orders.completed });
}));

// 服务中上报中断：填写原因和期望改到的时间，订单停在「待确认」
router.post('/:id/exceptions', authenticateToken, asyncHandler(async (req, res) => {
  const { reason, expected_time } = req.body;
  const orderId = req.params.id;
  const order = await findOrder(orderId);

  if (!order) {
    return res.status(404).json({ message: messages.orders.notFound });
  }

  if (order.user_id !== req.user.id && order.volunteer_id !== req.user.id) {
    return res.status(403).json({ message: messages.orders.forbidden });
  }

  if (order.status !== 'in_progress') {
    // 已有未处理异常时保留原记录，只提示等待处理
    if (order.status === 'pending_confirm') {
      return res.status(400).json({ message: messages.exceptions.pendingExists });
    }
    return res.status(400).json({ message: messages.exceptions.onlyInProgress });
  }

  if (!reason || !String(reason).trim() || !expected_time) {
    return res.status(400).json({ message: messages.exceptions.missingFields });
  }

  if (Number.isNaN(Date.parse(expected_time))) {
    return res.status(400).json({ message: messages.exceptions.invalidTime });
  }

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();

    const [pending] = await conn.query(
      "SELECT id FROM order_exceptions WHERE order_id = ? AND status = 'pending' FOR UPDATE",
      [orderId],
    );
    if (pending.length > 0) {
      await conn.rollback();
      return res.status(400).json({ message: messages.exceptions.pendingExists });
    }

    await conn.query(
      `INSERT INTO order_exceptions (order_id, reporter_id, reason, expected_resume_time, status)
       VALUES (?, ?, ?, ?, 'pending')`,
      [orderId, req.user.id, String(reason).trim(), expected_time],
    );

    await conn.query("UPDATE orders SET status = 'pending_confirm' WHERE id = ?", [orderId]);

    await conn.commit();
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }

  res.json({ message: messages.exceptions.reported });
}));

// 另一方处理异常：reschedule 确认改期沿用原志愿者；end 确认结束，需求重新等待认领
router.put('/:id/exceptions/resolve', authenticateToken, asyncHandler(async (req, res) => {
  const { action } = req.body;
  const orderId = req.params.id;
  const order = await findOrder(orderId);

  if (!order) {
    return res.status(404).json({ message: messages.orders.notFound });
  }

  if (order.user_id !== req.user.id && order.volunteer_id !== req.user.id) {
    return res.status(403).json({ message: messages.orders.forbidden });
  }

  const [pendingExceptions] = await pool.query(
    "SELECT * FROM order_exceptions WHERE order_id = ? AND status = 'pending' ORDER BY id DESC LIMIT 1",
    [orderId],
  );

  if (pendingExceptions.length === 0) {
    return res.status(400).json({ message: messages.exceptions.notPending });
  }

  const exception = pendingExceptions[0];

  // 上报方不能自行处理，只有另一方可以确认
  if (Number(exception.reporter_id) === Number(req.user.id)) {
    return res.status(403).json({ message: messages.exceptions.resolveByOther });
  }

  if (action !== 'reschedule' && action !== 'end') {
    return res.status(400).json({ message: messages.exceptions.invalidAction });
  }

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();

    if (action === 'reschedule') {
      const newTime = req.body.expected_time || exception.expected_resume_time;
      if (!newTime || Number.isNaN(Date.parse(newTime))) {
        await conn.rollback();
        return res.status(400).json({ message: messages.exceptions.invalidTime });
      }

      // 沿用原志愿者，只更新服务时间并恢复进行中
      await conn.query(
        "UPDATE needs SET expected_time = ?, status = 'accepted', volunteer_id = ? WHERE id = ?",
        [newTime, order.volunteer_id, order.need_id],
      );
      await conn.query("UPDATE orders SET status = 'in_progress' WHERE id = ?", [orderId]);
      await conn.query(
        "UPDATE order_exceptions SET status = 'resolved', resolution = 'reschedule', resolved_by = ?, resolved_at = NOW() WHERE id = ?",
        [req.user.id, exception.id],
      );

      await conn.commit();
      return res.json({ message: messages.exceptions.rescheduleConfirmed, expected_time: newTime });
    }

    // 确认结束：取消这次接单，不结算积分，需求重新开放认领
    await conn.query(
      "UPDATE needs SET status = 'pending', volunteer_id = NULL WHERE id = ?",
      [order.need_id],
    );
    await conn.query("UPDATE orders SET status = 'cancelled', end_time = NOW() WHERE id = ?", [orderId]);
    await conn.query(
      "UPDATE order_exceptions SET status = 'resolved', resolution = 'end', resolved_by = ?, resolved_at = NOW() WHERE id = ?",
      [req.user.id, exception.id],
    );

    await conn.commit();
    res.json({ message: messages.exceptions.endConfirmed });
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}));

router.post('/:id/review', authenticateToken, asyncHandler(async (req, res) => {
  const { rating, comment } = req.body;
  const orderId = req.params.id;
  const [orders] = await pool.query('SELECT * FROM orders WHERE id = ?', [orderId]);

  if (orders.length === 0) {
    return res.status(404).json({ message: messages.orders.notFound });
  }

  const targetId = orders[0].user_id === req.user.id
    ? orders[0].volunteer_id
    : orders[0].user_id;

  await pool.query(
    'INSERT INTO reviews (order_id, reviewer_id, target_id, rating, comment) VALUES (?, ?, ?, ?, ?)',
    [orderId, req.user.id, targetId, rating, comment],
  );

  res.json({ message: messages.orders.reviewed });
}));

module.exports = router;
