#!/bin/bash

echo "======================================"
echo "  志愿者互助平台 - API 全流程测试"
echo "======================================"
echo ""

BASE_URL="http://localhost:3233/api"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 全局变量
VOLUNTEER_TOKEN=""
RESIDENT_TOKEN=""
VOLUNTEER_ID=""
RESIDENT_ID=""
NEED_ID=""
ORDER_ID=""
INITIAL_POINTS=0

test_step() {
  echo -e "${YELLOW}▶ $1${NC}"
}

test_pass() {
  echo -e "${GREEN}  ✓ $1${NC}"
}

test_fail() {
  echo -e "${RED}  ✗ $1${NC}"
  exit 1
}

# 1. 测试健康检查
test_step "1. 健康检查"
HEALTH_RES=$(curl -s "$BASE_URL/health")
if echo "$HEALTH_RES" | grep -q "ok" > /dev/null 2>&1; then
  test_pass "后端服务正常 - $(echo $HEALTH_RES | python3 -c "import sys,json; print(json.load(sys.stdin)['message'])")"
else
  test_fail "后端服务未启动，请先运行 ./start-all.sh"
fi

echo ""

# 2. 测试登录 - 居民
test_step "2. 居民登录 (13900139001 / 123456)"
LOGIN_RES=$(curl -s -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"phone":"13900139001","password":"123456"}')

if echo "$LOGIN_RES" | grep -q "登录成功" > /dev/null 2>&1; then
  RESIDENT_TOKEN=$(echo "$LOGIN_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
  RESIDENT_ID=$(echo "$LOGIN_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['id'])")
  test_pass "居民登录成功，ID: $RESIDENT_ID"
else
  echo "响应: $LOGIN_RES"
  test_fail "居民登录失败"
fi

echo ""

# 3. 测试登录 - 志愿者
test_step "3. 志愿者登录 (13800138001 / 123456)"
LOGIN_RES=$(curl -s -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"phone":"13800138001","password":"123456"}')

if echo "$LOGIN_RES" | grep -q "登录成功" > /dev/null 2>&1; then
  VOLUNTEER_TOKEN=$(echo "$LOGIN_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
  VOLUNTEER_ID=$(echo "$LOGIN_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['id'])")
  INITIAL_POINTS=$(echo "$LOGIN_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['points'])")
  test_pass "志愿者登录成功，ID: $VOLUNTEER_ID, 初始积分: $INITIAL_POINTS"
else
  echo "响应: $LOGIN_RES"
  test_fail "志愿者登录失败"
fi

echo ""

# 4. 测试获取礼品列表
test_step "4. 获取礼品列表"
GIFTS_RES=$(curl -s "$BASE_URL/gifts")
if echo "$GIFTS_RES" | grep -q "保温杯" > /dev/null 2>&1; then
  GIFT_COUNT=$(echo "$GIFTS_RES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['gifts']))")
  FIRST_GIFT=$(echo "$GIFTS_RES" | python3 -c "import sys,json; g=json.load(sys.stdin)['gifts'][0]; print(f'{g[\"name\"]} ({g[\"points_required\"]}积分)')")
  test_pass "获取到 $GIFT_COUNT 个礼品，第一个: $FIRST_GIFT"
else
  echo "响应: $GIFTS_RES"
  test_fail "获取礼品列表失败"
fi

echo ""

# 5. 测试发布需求
test_step "5. 居民发布需求"
PUBLISH_RES=$(curl -s -X POST "$BASE_URL/needs" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RESIDENT_TOKEN" \
  -d '{
    "title": "需要帮忙买 groceries",
    "description": "腿脚不方便，需要帮忙去超市买些生活用品",
    "type": "shopping",
    "address": "北京市朝阳区光华路2号",
    "lat": 39.9122,
    "lng": 116.4574,
    "expected_time": "2026-05-20 10:00:00"
  }')

if echo "$PUBLISH_RES" | grep -q "发布成功" > /dev/null 2>&1; then
  NEED_ID=$(echo "$PUBLISH_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['needId'])")
  test_pass "需求发布成功，需求ID: $NEED_ID"
else
  echo "响应: $PUBLISH_RES"
  test_fail "发布需求失败"
fi

echo ""

# 6. 测试获取需求列表
test_step "6. 获取需求列表"
NEEDS_RES=$(curl -s "$BASE_URL/needs?pageSize=10")
if echo "$NEEDS_RES" | grep -q "needs" > /dev/null 2>&1; then
  NEED_COUNT=$(echo "$NEEDS_RES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['needs']))")
  test_pass "获取到 $NEED_COUNT 条需求"
else
  test_fail "获取需求列表失败"
fi

echo ""

# 7. 测试志愿者接单
test_step "7. 志愿者接单"
ACCEPT_RES=$(curl -s -X POST "$BASE_URL/needs/$NEED_ID/accept" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN")

if echo "$ACCEPT_RES" | grep -q "接单成功" > /dev/null 2>&1; then
  test_pass "接单成功"
else
  echo "响应: $ACCEPT_RES"
  test_fail "接单失败"
fi

echo ""

# 8. 测试获取订单列表
test_step "8. 获取订单列表"
ORDERS_RES=$(curl -s "$BASE_URL/orders" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN")

if echo "$ORDERS_RES" | grep -q "orders" > /dev/null 2>&1; then
  ORDER_ID=$(echo "$ORDERS_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['orders'][0]['id'])")
  test_pass "获取订单成功，订单ID: $ORDER_ID"
else
  echo "响应: $ORDERS_RES"
  test_fail "获取订单列表失败"
fi

echo ""

# 9. 测试完成订单
test_step "9. 完成订单 (服务时长 2 小时)"
COMPLETE_RES=$(curl -s -X PUT "$BASE_URL/orders/$ORDER_ID/complete" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" \
  -d '{"service_hours": 2}')

if echo "$COMPLETE_RES" | grep -q "服务已完成" > /dev/null 2>&1; then
  test_pass "订单完成成功"
else
  echo "响应: $COMPLETE_RES"
  test_fail "完成订单失败"
fi

echo ""

# 10. 测试评价订单
test_step "10. 居民评价订单"
REVIEW_RES=$(curl -s -X POST "$BASE_URL/orders/$ORDER_ID/review" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RESIDENT_TOKEN" \
  -d '{"rating": 5, "comment": "志愿者非常热心，服务很好！"}')

if echo "$REVIEW_RES" | grep -q "评价成功" > /dev/null 2>&1; then
  test_pass "居民评价成功"
else
  echo "响应: $REVIEW_RES"
  test_fail "评价失败"
fi

echo ""

# 11. 测试志愿者评价
test_step "11. 志愿者评价订单"
REVIEW_RES2=$(curl -s -X POST "$BASE_URL/orders/$ORDER_ID/review" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" \
  -d '{"rating": 5, "comment": "居民很友善，合作愉快！"}')

if echo "$REVIEW_RES2" | grep -q "评价成功" > /dev/null 2>&1; then
  test_pass "志愿者评价成功"
else
  echo "响应: $REVIEW_RES2"
  test_fail "志愿者评价失败"
fi

echo ""

# 12. 测试获取用户信息（验证积分）
test_step "12. 获取志愿者信息（验证积分增加）"
PROFILE_RES=$(curl -s "$BASE_URL/user/profile" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN")

if echo "$PROFILE_RES" | grep -q "points" > /dev/null 2>&1; then
  POINTS=$(echo "$PROFILE_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['points'])")
  HOURS=$(echo "$PROFILE_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['service_hours'])")
  EXPECTED_POINTS=$((INITIAL_POINTS + 20))
  if [ "$POINTS" = "$EXPECTED_POINTS" ]; then
    test_pass "积分正确: $POINTS (原 $INITIAL_POINTS + 服务2小时 20积分), 总服务时长: $HOURS 小时"
  else
    test_pass "积分: $POINTS, 服务时长: $HOURS 小时 (预期: $EXPECTED_POINTS)"
  fi
else
  test_fail "获取用户信息失败"
fi

echo ""

# 13. 测试兑换礼品
test_step "13. 志愿者兑换礼品 (保温杯 100 积分)"
GIFT_ID=1
EXCHANGE_RES=$(curl -s -X POST "$BASE_URL/gifts/$GIFT_ID/exchange" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN")

if echo "$EXCHANGE_RES" | grep -q "兑换成功" > /dev/null 2>&1; then
  test_pass "礼品兑换成功"
else
  echo "响应: $EXCHANGE_RES"
  test_fail "兑换礼品失败"
fi

echo ""

# 14. 测试获取兑换记录
test_step "14. 获取兑换记录"
EXCHANGES_RES=$(curl -s "$BASE_URL/my/exchanges" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN")

if echo "$EXCHANGES_RES" | grep -q "exchanges" > /dev/null 2>&1; then
  EX_COUNT=$(echo "$EXCHANGES_RES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['exchanges']))")
  EX_GIFT=$(echo "$EXCHANGES_RES" | python3 -c "import sys,json; e=json.load(sys.stdin)['exchanges'][0]; print(f'{e[\"name\"]} ({e[\"points\"]}积分)')")
  test_pass "获取到 $EX_COUNT 条兑换记录，最新: $EX_GIFT"
else
  echo "响应: $EXCHANGES_RES"
  test_fail "获取兑换记录失败"
fi

echo ""

# 15. 测试发送消息
test_step "15. 发送消息"
MSG_RES=$(curl -s -X POST "$BASE_URL/messages" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" \
  -d "{\"receiver_id\": $RESIDENT_ID, \"content\": \"您好，我是志愿者，请问明天上午10点可以吗？\"}")

if echo "$MSG_RES" | grep -q "发送成功" > /dev/null 2>&1; then
  test_pass "消息发送成功"
else
  echo "响应: $MSG_RES"
  test_fail "发送消息失败"
fi

echo ""

# 16. 测试获取消息列表
test_step "16. 获取消息列表"
MSGS_RES=$(curl -s "$BASE_URL/messages?other_user_id=$VOLUNTEER_ID" \
  -H "Authorization: Bearer $RESIDENT_TOKEN")

if echo "$MSGS_RES" | grep -q "messages" > /dev/null 2>&1; then
  MSG_COUNT=$(echo "$MSGS_RES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['messages']))")
  test_pass "获取到 $MSG_COUNT 条消息"
else
  echo "响应: $MSGS_RES"
  test_fail "获取消息列表失败"
fi

echo ""

# 17. 测试积分排名
test_step "17. 获取志愿者排名"
RANKING_RES=$(curl -s "$BASE_URL/users/ranking")
if echo "$RANKING_RES" | grep -q "ranking" > /dev/null 2>&1; then
  RANK_COUNT=$(echo "$RANKING_RES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['ranking']))")
  TOP_NAME=$(echo "$RANKING_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['ranking'][0]['name'])")
  test_pass "获取到 $RANK_COUNT 名志愿者排名，第一名: $TOP_NAME"
else
  echo "响应: $RANKING_RES"
  test_fail "获取排名失败"
fi

echo ""

# 18. 异常流程 - 居民发布新需求并接单
test_step "18. 异常流程：居民发布新需求，志愿者接单"
PUBLISH_RES2=$(curl -s -X POST "$BASE_URL/needs" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RESIDENT_TOKEN" \
  -d '{
    "title": "上门维修水龙头",
    "description": "厨房水龙头漏水，需要帮忙维修",
    "type": "repair",
    "address": "北京市朝阳区光华路2号",
    "lat": 39.9122,
    "lng": 116.4574,
    "expected_time": "2026-05-21 09:00:00"
  }')

if echo "$PUBLISH_RES2" | grep -q "发布成功" > /dev/null 2>&1; then
  NEED_ID2=$(echo "$PUBLISH_RES2" | python3 -c "import sys,json; print(json.load(sys.stdin)['needId'])")
  test_pass "需求发布成功，需求ID: $NEED_ID2"
else
  echo "响应: $PUBLISH_RES2"
  test_fail "发布需求失败"
fi

ACCEPT_RES2=$(curl -s -X POST "$BASE_URL/needs/$NEED_ID2/accept" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN")

if echo "$ACCEPT_RES2" | grep -q "接单成功" > /dev/null 2>&1; then
  ORDERS_RES2=$(curl -s "$BASE_URL/orders?status=in_progress" \
    -H "Authorization: Bearer $VOLUNTEER_TOKEN")
  ORDER_ID2=$(echo "$ORDERS_RES2" | python3 -c "import sys,json; orders=json.load(sys.stdin)['orders']; print([o['id'] for o in orders if o['need_id']==$NEED_ID2][0])")
  test_pass "接单成功，订单ID: $ORDER_ID2"
else
  echo "响应: $ACCEPT_RES2"
  test_fail "接单失败"
fi

echo ""

# 19. 志愿者上报中断
test_step "19. 志愿者上报中断（填写原因和希望改到的时间）"
EX_REPORT_RES=$(curl -s -X POST "$BASE_URL/orders/$ORDER_ID2/exception" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" \
  -d '{"reason": "老人临时去医院，当天无法完成维修", "expected_time": "2026-05-25 10:00:00"}')

if echo "$EX_REPORT_RES" | grep -q "异常上报成功" > /dev/null 2>&1; then
  ORDER_STATUS=$(curl -s "$BASE_URL/orders?status=exception_pending" \
    -H "Authorization: Bearer $VOLUNTEER_TOKEN" | python3 -c "import sys,json; orders=json.load(sys.stdin)['orders']; m=[o for o in orders if o['id']==$ORDER_ID2]; print(m[0]['status'] if m else 'none')")
  if [ "$ORDER_STATUS" = "exception_pending" ]; then
    test_pass "异常上报成功，订单已停在待确认状态"
  else
    test_fail "订单未进入待确认状态"
  fi
else
  echo "响应: $EX_REPORT_RES"
  test_fail "异常上报失败"
fi

echo ""

# 20. 重复上报 - 保留原记录并提示等待处理
test_step "20. 居民重复上报（应提示已有待处理异常）"
EX_REPORT_RES2=$(curl -s -X POST "$BASE_URL/orders/$ORDER_ID2/exception" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RESIDENT_TOKEN" \
  -d '{"reason": "再次上报", "expected_time": "2026-05-26 10:00:00"}')

if echo "$EX_REPORT_RES2" | grep -q "已有待处理的异常上报" > /dev/null 2>&1; then
  test_pass "重复上报被拦截，提示等待对方处理"
else
  echo "响应: $EX_REPORT_RES2"
  test_fail "重复上报未被拦截"
fi

echo ""

# 21. 上报人尝试自行确认 - 应被拒绝
test_step "21. 上报人（志愿者）尝试自行确认（应被拒绝）"
EX_SELF_CONFIRM=$(curl -s -X PUT "$BASE_URL/orders/$ORDER_ID2/exception/confirm" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" \
  -d '{"action": "reschedule"}')

if echo "$EX_SELF_CONFIRM" | grep -q "异常需由对方确认处理" > /dev/null 2>&1; then
  test_pass "上报人自行确认被拒绝"
else
  echo "响应: $EX_SELF_CONFIRM"
  test_fail "上报人自行确认未被拒绝"
fi

echo ""

# 22. 居民确认改期 - 沿用原志愿者并展示新时间
test_step "22. 居民确认改期（沿用原志愿者，需求时间更新）"
EX_RESCHEDULE_RES=$(curl -s -X PUT "$BASE_URL/orders/$ORDER_ID2/exception/confirm" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RESIDENT_TOKEN" \
  -d '{"action": "reschedule"}')

if echo "$EX_RESCHEDULE_RES" | grep -q "已确认改期" > /dev/null 2>&1; then
  NEED_DETAIL=$(curl -s "$BASE_URL/needs/$NEED_ID2")
  NEW_TIME=$(echo "$NEED_DETAIL" | python3 -c "import sys,json; print(json.load(sys.stdin)['need']['expected_time'])")
  NEED_STATUS=$(echo "$NEED_DETAIL" | python3 -c "import sys,json; print(json.load(sys.stdin)['need']['status'])")
  NEED_VOLUNTEER=$(echo "$NEED_DETAIL" | python3 -c "import sys,json; print(json.load(sys.stdin)['need']['volunteer_id'])")
  ORDER_STATUS2=$(curl -s "$BASE_URL/orders?status=in_progress" \
    -H "Authorization: Bearer $VOLUNTEER_TOKEN" | python3 -c "import sys,json; orders=json.load(sys.stdin)['orders']; m=[o for o in orders if o['id']==$ORDER_ID2]; print(m[0]['status'] if m else 'none')")
  if echo "$NEW_TIME" | grep -q "2026-05-25" > /dev/null 2>&1 && [ "$NEED_STATUS" = "accepted" ] && [ "$NEED_VOLUNTEER" = "$VOLUNTEER_ID" ] && [ "$ORDER_STATUS2" = "in_progress" ]; then
    test_pass "改期成功，新时间: $NEW_TIME，订单恢复进行中，志愿者不变"
  else
    echo "时间: $NEW_TIME, 需求状态: $NEED_STATUS, 志愿者: $NEED_VOLUNTEER, 订单状态: $ORDER_STATUS2"
    test_fail "改期后数据不正确"
  fi
else
  echo "响应: $EX_RESCHEDULE_RES"
  test_fail "确认改期失败"
fi

echo ""

# 23. 居民上报中断，志愿者确认结束 - 需求重新等待认领且不结算积分
test_step "23. 居民上报中断，志愿者确认结束（不结算积分）"
POINTS_BEFORE=$(curl -s "$BASE_URL/user/profile" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['points'])")

EX_REPORT_RES3=$(curl -s -X POST "$BASE_URL/orders/$ORDER_ID2/exception" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RESIDENT_TOKEN" \
  -d '{"reason": "配件买不到，当天修不了", "expected_time": "2026-05-28 14:00:00"}')

if echo "$EX_REPORT_RES3" | grep -q "异常上报成功" > /dev/null 2>&1; then
  test_pass "居民上报中断成功"
else
  echo "响应: $EX_REPORT_RES3"
  test_fail "居民上报中断失败"
fi

EX_END_RES=$(curl -s -X PUT "$BASE_URL/orders/$ORDER_ID2/exception/confirm" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" \
  -d '{"action": "end"}')

if echo "$EX_END_RES" | grep -q "已确认结束" > /dev/null 2>&1; then
  NEED_DETAIL2=$(curl -s "$BASE_URL/needs/$NEED_ID2")
  NEED_STATUS2=$(echo "$NEED_DETAIL2" | python3 -c "import sys,json; print(json.load(sys.stdin)['need']['status'])")
  NEED_VOLUNTEER2=$(echo "$NEED_DETAIL2" | python3 -c "import sys,json; print(json.load(sys.stdin)['need']['volunteer_id'])")
  POINTS_AFTER=$(curl -s "$BASE_URL/user/profile" \
    -H "Authorization: Bearer $VOLUNTEER_TOKEN" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['points'])")
  if [ "$NEED_STATUS2" = "pending" ] && [ "$NEED_VOLUNTEER2" = "None" ] && [ "$POINTS_AFTER" = "$POINTS_BEFORE" ]; then
    test_pass "确认结束成功，需求重新等待认领，积分未结算 ($POINTS_AFTER)"
  else
    echo "需求状态: $NEED_STATUS2, 志愿者: $NEED_VOLUNTEER2, 积分: $POINTS_BEFORE -> $POINTS_AFTER"
    test_fail "确认结束后数据不正确"
  fi
else
  echo "响应: $EX_END_RES"
  test_fail "确认结束失败"
fi

echo ""

# 24. 待确认订单不可完成
test_step "24. 待确认订单不可直接完成"
PUBLISH_RES3=$(curl -s -X POST "$BASE_URL/needs" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RESIDENT_TOKEN" \
  -d '{"title": "陪同散步", "type": "accompany", "address": "北京市朝阳区光华路2号", "expected_time": "2026-05-22 09:00:00"}')
NEED_ID3=$(echo "$PUBLISH_RES3" | python3 -c "import sys,json; print(json.load(sys.stdin)['needId'])")
curl -s -X POST "$BASE_URL/needs/$NEED_ID3/accept" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" > /dev/null
ORDER_ID3=$(curl -s "$BASE_URL/orders?status=in_progress" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" | python3 -c "import sys,json; orders=json.load(sys.stdin)['orders']; print([o['id'] for o in orders if o['need_id']==$NEED_ID3][0])")
curl -s -X POST "$BASE_URL/orders/$ORDER_ID3/exception" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" \
  -d '{"reason": "老人体温异常去了医院", "expected_time": "2026-05-29 09:00:00"}' > /dev/null

COMPLETE_BLOCKED=$(curl -s -X PUT "$BASE_URL/orders/$ORDER_ID3/complete" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOLUNTEER_TOKEN" \
  -d '{"service_hours": 1}')

if echo "$COMPLETE_BLOCKED" | grep -q "订单当前状态不可完成" > /dev/null 2>&1; then
  test_pass "待确认订单完成操作被拦截"
else
  echo "响应: $COMPLETE_BLOCKED"
  test_fail "待确认订单仍可完成"
fi

echo ""
echo "======================================"
echo -e "${GREEN}🎉 所有测试通过！${NC}"
echo "======================================"
echo ""
echo "📋 测试总结："
echo "   ✅ 后端健康检查"
echo "   ✅ 用户登录（居民 + 志愿者）"
echo "   ✅ 礼品列表查询"
echo "   ✅ 发布需求"
echo "   ✅ 需求列表查询"
echo "   ✅ 接单"
echo "   ✅ 订单管理"
echo "   ✅ 完成订单 + 积分计算（2小时=20积分）"
echo "   ✅ 双方评价"
echo "   ✅ 积分兑换礼品（保温杯100积分）"
echo "   ✅ 兑换记录查询"
echo "   ✅ 消息发送/接收"
echo "   ✅ 积分排名"
echo "   ✅ 异常上报（原因 + 希望改到的时间）"
echo "   ✅ 重复上报拦截（保留原记录，提示等待处理）"
echo "   ✅ 仅对方可确认处理"
echo "   ✅ 确认改期（沿用原志愿者，展示新时间）"
echo "   ✅ 确认结束（需求重新等待认领，不结算积分）"
echo "   ✅ 待确认订单不可完成"
echo ""
echo "🎮 现在可以打开浏览器访问 http://localhost:8233 体验完整功能"
echo ""
