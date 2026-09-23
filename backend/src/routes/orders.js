const { Router } = require('express');
const pool = require('../../db');
const messages = require('../constants/messages');
const { authenticateToken } = require('../middleware/auth');
const asyncHandler = require('../utils/asyncHandler');

const router = Router();

router.get('/', authenticateToken, asyncHandler(async (req, res) => {
  const { status } = req.query;
  let sql = `SELECT o.*, n.title, n.type, n.address, n.expected_time,
    u1.name as user_name, u2.name as volunteer_name,
    e.id as exception_id, e.reason as exception_reason,
    e.expected_time as exception_expected_time, e.reporter_id as exception_reporter_id
    FROM orders o
    LEFT JOIN needs n ON o.need_id = n.id
    LEFT JOIN users u1 ON o.user_id = u1.id
    LEFT JOIN users u2 ON o.volunteer_id = u2.id
    LEFT JOIN order_exceptions e ON e.order_id = o.id AND e.status = 'pending'
    WHERE o.user_id = ? OR o.volunteer_id = ?`;
  const params = [req.user.id, req.user.id];

  if (status) {
    sql += ' AND o.status = ?';
    params.push(status);
  }

  sql += ' ORDER BY o.created_at DESC';

  const [rows] = await pool.query(sql, params);
  res.json({ orders: rows });
}));

router.put('/:id/complete', authenticateToken, asyncHandler(async (req, res) => {
  const { service_hours } = req.body;
  const orderId = req.params.id;
  const [orders] = await pool.query('SELECT * FROM orders WHERE id = ?', [orderId]);

  if (orders.length === 0) {
    return res.status(404).json({ message: messages.orders.notFound });
  }

  if (orders[0].user_id !== req.user.id && orders[0].volunteer_id !== req.user.id) {
    return res.status(403).json({ message: messages.orders.forbidden });
  }

  if (orders[0].status !== 'in_progress') {
    return res.status(400).json({ message: messages.orders.notCompletable });
  }

  await pool.query(
    "UPDATE orders SET status = 'completed', service_hours = ? WHERE id = ?",
    [service_hours || 1, orderId],
  );

  await pool.query(
    "UPDATE needs SET status = 'completed' WHERE id = ?",
    [orders[0].need_id],
  );

  const hours = service_hours || 1;
  await pool.query(
    'UPDATE users SET service_hours = service_hours + ?, points = points + ? WHERE id = ?',
    [hours, hours * 10, orders[0].volunteer_id],
  );

  res.json({ message: messages.orders.completed });
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

router.post('/:id/exception', authenticateToken, asyncHandler(async (req, res) => {
  const { reason, expected_time } = req.body;
  const orderId = req.params.id;
  const [orders] = await pool.query('SELECT * FROM orders WHERE id = ?', [orderId]);

  if (orders.length === 0) {
    return res.status(404).json({ message: messages.orders.notFound });
  }

  if (orders[0].user_id !== req.user.id && orders[0].volunteer_id !== req.user.id) {
    return res.status(403).json({ message: messages.orders.forbidden });
  }

  const [pending] = await pool.query(
    "SELECT id FROM order_exceptions WHERE order_id = ? AND status = 'pending'",
    [orderId],
  );

  if (pending.length > 0) {
    return res.status(400).json({ message: messages.orders.exceptionExists });
  }

  if (orders[0].status !== 'in_progress') {
    return res.status(400).json({ message: messages.orders.exceptionNotAllowed });
  }

  if (!reason || !expected_time) {
    return res.status(400).json({ message: messages.orders.exceptionMissingFields });
  }

  await pool.query(
    "INSERT INTO order_exceptions (order_id, reporter_id, reason, expected_time, status) VALUES (?, ?, ?, ?, 'pending')",
    [orderId, req.user.id, reason, expected_time],
  );

  await pool.query(
    "UPDATE orders SET status = 'exception_pending' WHERE id = ?",
    [orderId],
  );

  res.json({ message: messages.orders.exceptionReported });
}));

router.put('/:id/exception/confirm', authenticateToken, asyncHandler(async (req, res) => {
  const { action } = req.body;
  const orderId = req.params.id;
  const [orders] = await pool.query('SELECT * FROM orders WHERE id = ?', [orderId]);

  if (orders.length === 0) {
    return res.status(404).json({ message: messages.orders.notFound });
  }

  if (orders[0].user_id !== req.user.id && orders[0].volunteer_id !== req.user.id) {
    return res.status(403).json({ message: messages.orders.forbidden });
  }

  const [exceptions] = await pool.query(
    "SELECT * FROM order_exceptions WHERE order_id = ? AND status = 'pending' ORDER BY created_at DESC LIMIT 1",
    [orderId],
  );

  if (exceptions.length === 0) {
    return res.status(400).json({ message: messages.orders.exceptionNotFound });
  }

  const exception = exceptions[0];

  if (exception.reporter_id === req.user.id) {
    return res.status(403).json({ message: messages.orders.exceptionHandleForbidden });
  }

  if (action === 'reschedule') {
    await pool.query(
      "UPDATE order_exceptions SET status = 'rescheduled', handler_id = ?, handled_at = NOW() WHERE id = ?",
      [req.user.id, exception.id],
    );

    await pool.query(
      "UPDATE orders SET status = 'in_progress' WHERE id = ?",
      [orderId],
    );

    await pool.query(
      'UPDATE needs SET expected_time = ? WHERE id = ?',
      [exception.expected_time, orders[0].need_id],
    );

    return res.json({ message: messages.orders.exceptionRescheduled });
  }

  if (action === 'end') {
    await pool.query(
      "UPDATE order_exceptions SET status = 'ended', handler_id = ?, handled_at = NOW() WHERE id = ?",
      [req.user.id, exception.id],
    );

    await pool.query(
      "UPDATE orders SET status = 'cancelled' WHERE id = ?",
      [orderId],
    );

    await pool.query(
      "UPDATE needs SET status = 'pending', volunteer_id = NULL WHERE id = ?",
      [orders[0].need_id],
    );

    return res.json({ message: messages.orders.exceptionEnded });
  }

  res.status(400).json({ message: messages.orders.exceptionInvalidAction });
}));

module.exports = router;
