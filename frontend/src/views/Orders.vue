<template>
  <div class="min-h-screen bg-gray-50">
    <div class="container mx-auto px-4 py-6">
      <h1 class="text-2xl font-bold text-gray-800 mb-6">我的订单</h1>

      <el-card class="mb-6">
        <el-tabs v-model="activeTab" @tab-change="fetchOrders">
          <el-tab-pane label="进行中" name="in_progress" />
          <el-tab-pane label="待确认" name="pending_confirm" />
          <el-tab-pane label="已完成" name="completed" />
          <el-tab-pane label="已取消" name="cancelled" />
          <el-tab-pane label="全部" name="" />
        </el-tabs>
      </el-card>

      <div v-if="loading" class="text-center py-16">
        <el-icon class="animate-spin text-4xl text-gray-400"><Loading /></el-icon>
      </div>

      <div v-else-if="orders.length === 0" class="text-center py-16">
        <el-icon class="text-6xl text-gray-300"><Document /></el-icon>
        <p class="mt-4 text-gray-500">暂无订单</p>
      </div>

      <div v-else class="space-y-4">
        <el-card v-for="order in orders" :key="order.id" class="hover:shadow-md">
          <div class="flex items-start justify-between">
            <div class="flex-1">
              <div class="flex items-center mb-2 flex-wrap gap-2">
                <h3 class="font-medium text-lg mr-1">{{ order.title }}</h3>
                <el-tag :type="getTypeColor(order.type)" size="small">
                  {{ getTypeName(order.type) }}
                </el-tag>
                <el-tag v-if="order.status === 'in_progress'" type="warning" size="small">进行中</el-tag>
                <el-tag v-else-if="order.status === 'pending_confirm'" type="danger" size="small">中断待确认</el-tag>
                <el-tag v-else-if="order.status === 'completed'" type="success" size="small">已完成</el-tag>
                <el-tag v-else-if="order.status === 'cancelled'" type="info" size="small">已取消</el-tag>
              </div>

              <div class="text-gray-600 text-sm mb-3">
                <p v-if="user?.role === 'volunteer'">
                  <el-icon class="mr-1"><User /></el-icon>
                  服务对象：{{ order.user_name }}
                </p>
                <p v-else>
                  <el-icon class="mr-1"><Service /></el-icon>
                  志愿者：{{ order.volunteer_name }}
                </p>
                <p class="mt-1">
                  <el-icon class="mr-1"><Location /></el-icon>
                  {{ order.address }}
                </p>
                <p v-if="order.expected_time" class="mt-1">
                  <el-icon class="mr-1"><Clock /></el-icon>
                  约定服务时间：{{ new Date(order.expected_time).toLocaleString() }}
                </p>
                <p v-if="order.service_hours" class="mt-1">
                  <el-icon class="mr-1"><Timer /></el-icon>
                  服务时长：{{ order.service_hours }} 小时
                </p>
              </div>

              <!-- 中断异常信息 -->
              <el-alert
                v-if="order.exception_id"
                class="mb-3"
                type="warning"
                :closable="false"
                show-icon
              >
                <template #title>
                  <span>
                    {{ Number(order.exception_reporter_id) === user?.id ? '我' : '对方' }}上报了服务中断
                  </span>
                </template>
                <div class="text-sm mt-1">
                  <p>中断原因：{{ order.exception_reason }}</p>
                  <p>期望改到：{{ new Date(order.exception_expected_time).toLocaleString() }}</p>
                  <p class="text-gray-400">
                    上报时间：{{ new Date(order.exception_created_at).toLocaleString() }}
                  </p>
                  <p v-if="Number(order.exception_reporter_id) === user?.id" class="mt-1 text-orange-600">
                    已提交，等待对方处理，暂时不能重复上报
                  </p>
                </div>
              </el-alert>

              <div class="text-xs text-gray-400">
                下单时间：{{ new Date(order.created_at).toLocaleString() }}
              </div>
            </div>

            <div class="flex flex-col gap-2 ml-4">
              <el-button
                v-if="order.status === 'in_progress'"
                type="primary"
                size="small"
                @click="handleComplete(order)"
              >
                完成服务
              </el-button>
              <el-button
                v-if="order.status === 'in_progress'"
                type="warning"
                size="small"
                @click="showExceptionDialog(order)"
              >
                上报中断
              </el-button>
              <template v-if="order.status === 'pending_confirm' && Number(order.exception_reporter_id) !== user?.id">
                <el-button type="primary" size="small" @click="handleReschedule(order)">
                  确认改期
                </el-button>
                <el-button type="danger" size="small" @click="handleEnd(order)">
                  确认结束
                </el-button>
              </template>
              <el-button
                v-if="order.status === 'completed' && !hasReviewed(order.id)"
                type="success"
                size="small"
                @click="showReviewDialog(order)"
              >
                去评价
              </el-button>
              <el-button
                type="text"
                size="small"
                @click="handleMessage(order)"
              >
                <el-icon class="mr-1"><ChatDotRound /></el-icon>
                发消息
              </el-button>
            </div>
          </div>
        </el-card>
      </div>
    </div>

    <el-dialog v-model="reviewDialogVisible" title="服务评价" width="500px">
      <el-form :model="reviewForm" label-width="80px">
        <el-form-item label="评分">
          <el-rate v-model="reviewForm.rating" :max="5" show-score />
        </el-form-item>
        <el-form-item label="评价内容">
          <el-input v-model="reviewForm.comment" type="textarea" :rows="3" placeholder="请输入评价内容" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="reviewDialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="submittingReview" @click="submitReview">提交评价</el-button>
      </template>
    </el-dialog>

    <el-dialog v-model="exceptionDialogVisible" title="上报服务中断" width="500px">
      <el-form :model="exceptionForm" label-width="100px">
        <el-form-item label="中断原因" required>
          <el-input
            v-model="exceptionForm.reason"
            type="textarea"
            :rows="3"
            maxlength="200"
            show-word-limit
            placeholder="例如：老人临时去医院、当天维修处理不了"
          />
        </el-form-item>
        <el-form-item label="期望改到" required>
          <el-date-picker
            v-model="exceptionForm.expected_time"
            type="datetime"
            placeholder="选择希望改到的时间"
            format="YYYY-MM-DD HH:mm"
            value-format="YYYY-MM-DD HH:mm:ss"
            class="w-full"
          />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="exceptionDialogVisible = false">取消</el-button>
        <el-button type="warning" :loading="submittingException" @click="submitException">提交上报</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { useUserStore } from '@/stores/user'
import api from '@/utils/api'
import { ElMessage, ElMessageBox } from 'element-plus'

const router = useRouter()
const userStore = useUserStore()
const user = computed(() => userStore.user)

const orders = ref([])
const loading = ref(false)
const activeTab = ref('in_progress')
const reviewDialogVisible = ref(false)
const submittingReview = ref(false)
const currentOrder = ref(null)
const reviewedOrders = ref([])

const exceptionDialogVisible = ref(false)
const submittingException = ref(false)

const reviewForm = ref({
  rating: 5,
  comment: ''
})

const exceptionForm = ref({
  reason: '',
  expected_time: ''
})

const typeMap = {
  accompany: { name: '陪聊陪诊', color: 'blue' },
  shopping: { name: '代买代办', color: 'green' },
  repair: { name: '家电维修', color: 'orange' },
  housework: { name: '家政服务', color: 'purple' },
  other: { name: '其他帮助', color: 'gray' }
}

const getTypeName = (type) => typeMap[type]?.name || type
const getTypeColor = (type) => typeMap[type]?.color || 'info'

const hasReviewed = (orderId) => reviewedOrders.value.includes(orderId)

const fetchOrders = async () => {
  loading.value = true
  try {
    const params = activeTab.value ? { status: activeTab.value } : {}
    const res = await api.get('/orders', { params })
    orders.value = res.data.orders
  } finally {
    loading.value = false
  }
}

const handleComplete = async (order) => {
  try {
    await ElMessageBox.confirm('确认服务已完成吗？', '完成确认', {
      confirmButtonText: '确定',
      cancelButtonText: '取消',
      type: 'info'
    })

    await api.put(`/orders/${order.id}/complete`, { service_hours: 1 })
    ElMessage.success('服务已完成')
    fetchOrders()
    userStore.fetchUserInfo()
  } catch (e) {
    if (e !== 'cancel') {
      ElMessage.error(e.response?.data?.message || '操作失败')
    }
  }
}

const showExceptionDialog = (order) => {
  currentOrder.value = order
  exceptionForm.value = { reason: '', expected_time: '' }
  exceptionDialogVisible.value = true
}

const submitException = async () => {
  if (!exceptionForm.value.reason.trim()) {
    ElMessage.warning('请填写中断原因')
    return
  }
  if (!exceptionForm.value.expected_time) {
    ElMessage.warning('请选择希望改到的时间')
    return
  }

  try {
    submittingException.value = true
    await api.post(`/orders/${currentOrder.value.id}/exceptions`, exceptionForm.value)
    ElMessage.success('中断已上报，等待对方确认')
    exceptionDialogVisible.value = false
    fetchOrders()
  } catch (e) {
    // 已有未处理异常时保留原记录，仅提示等待处理
    ElMessage.error(e.response?.data?.message || '上报失败')
  } finally {
    submittingException.value = false
  }
}

const handleReschedule = async (order) => {
  const newTime = new Date(order.exception_expected_time).toLocaleString()
  try {
    await ElMessageBox.confirm(
      `确认改期到 ${newTime} 吗？将沿用原志愿者安排服务。`,
      '确认改期',
      {
        confirmButtonText: '确认改期',
        cancelButtonText: '取消',
        type: 'warning'
      }
    )

    await api.put(`/orders/${order.id}/exceptions/resolve`, { action: 'reschedule' })
    ElMessage.success('已确认改期')
    fetchOrders()
  } catch (e) {
    if (e !== 'cancel') {
      ElMessage.error(e.response?.data?.message || '操作失败')
    }
  }
}

const handleEnd = async (order) => {
  try {
    await ElMessageBox.confirm(
      '确认结束本次接单吗？该需求将重新开放认领，本次服务不结算积分。',
      '确认结束',
      {
        confirmButtonText: '确认结束',
        cancelButtonText: '取消',
        type: 'warning'
      }
    )

    await api.put(`/orders/${order.id}/exceptions/resolve`, { action: 'end' })
    ElMessage.success('已结束接单，需求重新等待认领')
    fetchOrders()
  } catch (e) {
    if (e !== 'cancel') {
      ElMessage.error(e.response?.data?.message || '操作失败')
    }
  }
}

const showReviewDialog = (order) => {
  currentOrder.value = order
  reviewForm.value = { rating: 5, comment: '' }
  reviewDialogVisible.value = true
}

const submitReview = async () => {
  try {
    submittingReview.value = true
    await api.post(`/orders/${currentOrder.value.id}/review`, reviewForm.value)
    reviewedOrders.value.push(currentOrder.value.id)
    ElMessage.success('评价成功')
    reviewDialogVisible.value = false
  } catch (e) {
    ElMessage.error(e.response?.data?.message || '评价失败')
  } finally {
    submittingReview.value = false
  }
}

const handleMessage = (order) => {
  const otherUserId = user.value.role === 'volunteer' ? order.user_id : order.volunteer_id
  router.push({
    path: '/messages',
    query: { userId: otherUserId }
  })
}

onMounted(() => {
  fetchOrders()
})
</script>
