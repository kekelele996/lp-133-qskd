const pool = require('../../db');
const logger = require('../utils/logger');

// 兼容已存在的数据库：补齐异常处理所需的字段和表
const ensureSchema = async () => {
  const [columns] = await pool.query(
    `SELECT COLUMN_TYPE FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orders' AND COLUMN_NAME = 'status'`,
  );

  if (columns.length > 0 && !columns[0].COLUMN_TYPE.includes('pending_confirm')) {
    await pool.query(
      `ALTER TABLE orders
       MODIFY COLUMN status ENUM('in_progress', 'pending_confirm', 'completed', 'cancelled')
       DEFAULT 'in_progress' COMMENT '状态'`,
    );
    logger.info('订单表状态已补充 pending_confirm');
  }

  await pool.query(
    `CREATE TABLE IF NOT EXISTS order_exceptions (
      id INT PRIMARY KEY AUTO_INCREMENT,
      order_id INT NOT NULL COMMENT '订单ID',
      reporter_id INT NOT NULL COMMENT '上报人ID(居民或志愿者)',
      reason VARCHAR(500) NOT NULL COMMENT '中断原因',
      expected_resume_time DATETIME COMMENT '期望改到的时间',
      status ENUM('pending', 'resolved') DEFAULT 'pending' COMMENT '处理状态',
      resolution ENUM('reschedule', 'end') COMMENT '处理结果: reschedule-改期, end-结束',
      resolved_by INT COMMENT '处理人ID',
      resolved_at DATETIME COMMENT '处理时间',
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (order_id) REFERENCES orders(id),
      FOREIGN KEY (reporter_id) REFERENCES users(id),
      FOREIGN KEY (resolved_by) REFERENCES users(id),
      INDEX idx_order_id (order_id),
      INDEX idx_status (status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='订单异常记录表'`,
  );
};

module.exports = ensureSchema;
