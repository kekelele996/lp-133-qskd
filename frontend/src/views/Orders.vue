<template>
  <div class="min-h-screen bg-gray-50">
    <div class="container mx-auto px-4 py-6">
      <h1 class="text-2xl font-bold text-gray-800 mb-6">我的订单</h1>
      
      <el-card class="mb-6">
        <el-tabs v-model="activeTab" @tab-change="fetchOrders">
          <el-tab-pane label="进行中" name="in_progress" />
          <el-tab-pane label="待确认" name="exception_pending" />
          <el-tab-pane label="已完成" name="completed" />
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
              <div class="flex items-center mb-2">
                <h3 class="font-medium text-lg mr-3">{{ order.title }}</h3>
                <el-tag :type="getTypeColor(order.type)" size="small">
                  {{ getTypeName(order.type) }}
                </el-tag>
                <el-tag v-if="order.status === 'in_progress'" type="warning" class="ml-2" size="small">进行中</el-tag>
                <el-tag v-else-if="order.status === 'exception_pending'" type="danger" class="ml-2" size="small">异常待确认</el-tag>
                <el-tag v-else-if="order.status === 'completed'" type="success" class="ml-2" size="small">已完成</el-tag>
                <el-tag v-else-if="order.status === 'cancelled'" type="info" class="ml-2" size="small">已取消</el-tag>
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
                  <el-icon class="mr-1"><Calendar /></el-icon>
                  期望时间：{{ new Date(order.expected_time).toLocaleString() }}
                </p>
                <p v-if="order.service_hours" class="mt-1">
                  <el-icon class="mr-1"><Clock /></el-icon>
                  服务时长：{{ order.service_hours }} 小时
                </p>
              </div>

              <div v-if="order.exception_id" class="mt-3 p-3 bg-red-50 rounded text-sm">
                <p class="text-red-600 font-medium mb-1">异常中断上报</p>
                <p class="text-gray-600">中断原因：{{ order.exception_reason }}</p>
                <p class="text-gray-600 mt-1">
                  希望改到：{{ new Date(order.exception_expected_time).toLocaleString() }}
                </p>
                <p v-if="isMyReport(order)" class="text-gray-400 text-xs mt-2">
                  我已上报，等待对方处理
                </p>
                <p v-else class="text-gray-400 text-xs mt-2">
                  对方已上报中断，请确认改期或结束
                </p>
              </div>
              
              <div class="text-xs text-gray-400">
                下单时间：{{ new Date(order.created_at).toLocaleString() }}
              </div>
            </div>
            
            <div class="flex flex-col gap-2">
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
              <template v-if="order.status === 'exception_pending' && order.exception_id && !isMyReport(order)">
                <el-button
                  type="primary"
                  size="small"
                  @click="handleConfirmException(order, 'reschedule')"
                >
                  确认改期
                </el-button>
                <el-button
                  type="danger"
                  size="small"
                  @click="handleConfirmException(order, 'end')"
                >
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
            placeholder="请说明中断原因，如老人临时去医院、当天无法完成维修等"
          />
        </el-form-item>
        <el-form-item label="希望改到" required>
          <el-date-picker
            v-model="exceptionForm.expected_time"
            type="datetime"
            placeholder="选择希望改到的时间"
            value-format="YYYY-MM-DD HH:mm:ss"
            style="width: 100%"
          />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="exceptionDialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="submittingException" @click="submitException">提交上报</el-button>
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

const isMyReport = (order) => order.exception_reporter_id === user.value?.id

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

const showReviewDialog = (order) => {
  currentOrder.value = order
  reviewForm.value = { rating: 5, comment: '' }
  reviewDialogVisible.value = true
}

const showExceptionDialog = (order) => {
  currentOrder.value = order
  exceptionForm.value = { reason: '', expected_time: '' }
  exceptionDialogVisible.value = true
}

const submitException = async () => {
  if (!exceptionForm.value.reason || !exceptionForm.value.expected_time) {
    ElMessage.warning('请填写中断原因和希望改到的时间')
    return
  }

  try {
    submittingException.value = true
    await api.post(`/orders/${currentOrder.value.id}/exception`, exceptionForm.value)
    ElMessage.success('异常上报成功，请等待对方处理')
    exceptionDialogVisible.value = false
    fetchOrders()
  } catch (e) {
    ElMessage.error(e.response?.data?.message || '上报失败')
  } finally {
    submittingException.value = false
  }
}

const handleConfirmException = async (order, action) => {
  const isReschedule = action === 'reschedule'
  const newTime = order.exception_expected_time
    ? new Date(order.exception_expected_time).toLocaleString()
    : ''

  try {
    await ElMessageBox.confirm(
      isReschedule
        ? `确认改期到 ${newTime} 吗？仍由原志愿者继续服务。`
        : '确认结束本次服务吗？需求将重新等待认领，且不结算积分。',
      isReschedule ? '确认改期' : '确认结束',
      {
        confirmButtonText: '确定',
        cancelButtonText: '取消',
        type: isReschedule ? 'info' : 'warning'
      }
    )

    const res = await api.put(`/orders/${order.id}/exception/confirm`, { action })
    ElMessage.success(res.data?.message || (isReschedule ? '已确认改期' : '已确认结束'))
    fetchOrders()
  } catch (e) {
    if (e !== 'cancel') {
      ElMessage.error(e.response?.data?.message || '操作失败')
    }
  }
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
