// BusTicketBooking - Web Management Portal Application
const API_BASE = window.location.origin;

// State
let token = localStorage.getItem('btb_token') || '';
let currentUser = JSON.parse(localStorage.getItem('btb_user') || 'null');
let activeTab = 'dashboard';

let appState = {
  summary: null,
  dashboard: null,
  trips: [],
  bookings: [],
  buses: [],
  routes: [],
  drivers: [],
  parcels: [],
  companies: [],
  users: [],
  refunds: [],
  promotions: [],
  acceptance: [],
  auditLogs: []
};

// Charts
let revenueChart = null;
let ticketChart = null;

// Helper: Format Currency (VND)
function formatVND(amount) {
  if (amount === undefined || amount === null) return '0 đ';
  return Number(amount).toLocaleString('vi-VN') + ' đ';
}

// Helper: Format Date/Time
function formatDateTime(isoString) {
  if (!isoString) return '--';
  const d = new Date(isoString);
  return d.toLocaleString('vi-VN', {
    day: '2-digit', month: '2-digit', year: 'numeric',
    hour: '2-digit', minute: '2-digit'
  });
}

// Toast Notifications
function showToast(message, type = 'success') {
  const container = document.getElementById('toastContainer');
  if (!container) return;

  const toast = document.createElement('div');
  const bg = type === 'success' ? 'bg-emerald-600 text-white' : type === 'error' ? 'bg-rose-600 text-white' : 'bg-sky-600 text-white';
  const icon = type === 'success' ? 'check-circle' : type === 'error' ? 'alert-triangle' : 'info';

  toast.className = `${bg} px-4 py-2.5 rounded-xl shadow-lg flex items-center space-x-2 text-xs font-semibold pointer-events-auto transform transition-all duration-300 translate-y-2 opacity-0`;
  toast.innerHTML = `<i data-lucide="${icon}" class="w-4 h-4"></i><span>${message}</span>`;
  container.appendChild(toast);
  lucide.createIcons();

  requestAnimationFrame(() => {
    toast.classList.remove('translate-y-2', 'opacity-0');
  });

  setTimeout(() => {
    toast.classList.add('opacity-0', 'translate-y-2');
    setTimeout(() => toast.remove(), 300);
  }, 4000);
}

// API Call Wrapper
async function api(path, options = {}) {
  const headers = {
    'Content-Type': 'application/json',
    ...(options.headers || {})
  };

  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }

  try {
    const response = await fetch(`${API_BASE}${path}`, {
      ...options,
      headers
    });

    if (response.status === 401) {
      logout();
      showToast('Phiên làm việc hết hạn. Vui lòng đăng nhập lại.', 'error');
      throw new Error('Unauthorized');
    }

    if (!response.ok) {
      let errMsg = 'Thao tác không thành công';
      try {
        const errObj = await response.json();
        errMsg = errObj.message || errObj.title || JSON.stringify(errObj);
      } catch (e) {
        errMsg = await response.text();
      }
      throw new Error(errMsg);
    }

    const contentType = response.headers.get('content-type');
    if (contentType && contentType.includes('application/json')) {
      return await response.json();
    }
    return await response.text();
  } catch (err) {
    console.error(`API Error on ${path}:`, err);
    throw err;
  }
}

// Modal Handlers
function openModal(id) {
  const modal = document.getElementById(id);
  if (modal) {
    modal.classList.remove('hidden');
    populateModalSelects(id);
    lucide.createIcons();
  }
}

function closeModal(id) {
  const modal = document.getElementById(id);
  if (modal) modal.classList.add('hidden');
}

// Navigation Tab Switcher
function switchTab(tabId) {
  activeTab = tabId;
  document.querySelectorAll('.tab-pane').forEach(el => el.classList.add('hidden'));
  const target = document.getElementById(`tab-${tabId}`);
  if (target) target.classList.remove('hidden');

  // Sidebar link highlight
  document.querySelectorAll('.nav-item').forEach(btn => {
    btn.className = 'nav-item w-full flex items-center space-x-3 px-3 py-2 rounded-xl text-slate-600 hover:bg-slate-100 transition';
  });
  const activeNav = document.getElementById(`nav-${tabId}`);
  if (activeNav) {
    activeNav.className = 'nav-item w-full flex items-center space-x-3 px-3 py-2 rounded-xl text-sky-700 bg-sky-100/80 font-semibold transition';
  }

  // Load specific tab data
  if (tabId === 'trips') renderTripsTable();
  if (tabId === 'bookings') renderBookingsTable();
  if (tabId === 'buses') renderBuses();
  if (tabId === 'routes') renderRoutes();
  if (tabId === 'drivers') renderDrivers();
  if (tabId === 'parcels') renderParcels();
  if (tabId === 'companies') renderCompanies();
  if (tabId === 'users') renderUsers();
  if (tabId === 'refunds') renderRefunds();
  if (tabId === 'promotions') renderPromotions();
  if (tabId === 'acceptance') renderAcceptanceCriteria();
  if (tabId === 'auditlogs') renderAuditLogs();
  if (tabId === 'pos') setupPosCounter();

  lucide.createIcons();
}

// Authentication Handlers
async function handleLoginSubmit(e) {
  e.preventDefault();
  const email = document.getElementById('loginEmail').value.trim();
  const password = document.getElementById('loginPassword').value;
  await performLogin(email, password);
}

async function quickLogin(email, password) {
  await performLogin(email, password);
}

async function performLogin(email, password) {
  try {
    const res = await api('/api/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email, password })
    });

    token = res.accessToken;
    currentUser = res.user;
    localStorage.setItem('btb_token', token);
    localStorage.setItem('btb_user', JSON.stringify(currentUser));

    document.getElementById('loginModal').classList.add('hidden');
    updateUserUI();
    showToast(`Đăng nhập thành công với vai trò ${currentUser.roles?.join(', ')}`);
    await loadAllData();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

function logout() {
  token = '';
  currentUser = null;
  localStorage.removeItem('btb_token');
  localStorage.removeItem('btb_user');
  document.getElementById('loginModal').classList.remove('hidden');
  updateUserUI();
}

function updateUserUI() {
  const avatar = document.getElementById('userAvatar');
  const name = document.getElementById('userDisplayName');
  const role = document.getElementById('userRoleName');
  const sidebarCompany = document.getElementById('sidebarCompanyName');
  const adminSection = document.getElementById('adminNavSection');

  if (!currentUser) {
    avatar.textContent = '??';
    name.textContent = 'Chưa đăng nhập';
    role.textContent = 'Vui lòng xác thực';
    sidebarCompany.textContent = 'Chưa chọn';
    return;
  }

  const initials = currentUser.fullName ? currentUser.fullName.split(' ').map(p => p[0]).slice(-2).join('').toUpperCase() : 'US';
  avatar.textContent = initials;
  name.textContent = currentUser.fullName || currentUser.email;

  const isAdmin = currentUser.roles && currentUser.roles.includes('Admin');
  role.textContent = isAdmin ? 'Admin Toàn Quyền' : (currentUser.companyName || 'Nhà xe Đối tác');
  sidebarCompany.textContent = isAdmin ? 'Toàn Nền Tảng (Admin)' : (currentUser.companyName || 'Nhà xe');

  // Toggle admin section in sidebar
  if (adminSection) {
    adminSection.style.display = isAdmin ? 'block' : 'none';
  }
}

// Load All System Data
async function loadAllData() {
  if (!token) {
    document.getElementById('loginModal').classList.remove('hidden');
    return;
  }

  try {
    // 1. Load Financial & Operational Summary
    appState.summary = await api('/api/reports/summary');
    updateDashboardMetrics();

    // 2. Load Operator Dashboard (Trips, Buses, Drivers, Routes, Bookings)
    try {
      appState.dashboard = await api('/api/operator/dashboard');
      appState.buses = appState.dashboard.buses || [];
      appState.routes = appState.dashboard.routes || [];
      appState.drivers = appState.dashboard.drivers || [];
      appState.trips = appState.dashboard.trips || [];
      appState.bookings = appState.dashboard.bookings || [];
    } catch (e) {
      console.warn('Operator dashboard error (might be admin without company scope):', e);
    }

    // 3. Load Trips from public/operator
    try {
      const tripsList = await api('/api/trips');
      if (tripsList && tripsList.length) {
        appState.trips = tripsList;
      }
    } catch (e) {}

    // 4. Load Admin specific items if admin
    const isAdmin = currentUser && currentUser.roles && currentUser.roles.includes('Admin');
    if (isAdmin) {
      try {
        appState.companies = await api('/api/admin/companies');
        appState.users = await api('/api/admin/users');
        appState.refunds = await api('/api/admin/refunds');
        appState.promotions = await api('/api/admin/promotions');
        appState.acceptance = await api('/api/admin/acceptance-criteria');
        appState.auditLogs = await api('/api/admin/audit-logs');
      } catch (e) {
        console.warn('Admin endpoints load warning:', e);
      }
    }

    // 5. Load Parcels
    try {
      appState.parcels = await api('/api/operator/parcels');
    } catch (e) {}

    // Re-render active tab
    renderDashboardCharts();
    renderCompanyBreakdownTable();
    switchTab(activeTab);

  } catch (err) {
    console.error('loadAllData error:', err);
    showToast(err.message, 'error');
  }
}

// Update Dashboard Statistics Cards
function updateDashboardMetrics() {
  if (!appState.summary) return;
  const { financials, bookingMetrics, tripMetrics } = appState.summary;

  document.getElementById('statNetRevenue').textContent = formatVND(financials?.netCollectedRevenue || 0);
  document.getElementById('statTicketsSold').textContent = `${bookingMetrics?.totalTicketsSold || 0} vé`;
  document.getElementById('statConfirmedBookings').textContent = `${bookingMetrics?.confirmedBookings || 0} đơn đặt`;
  
  const occ = tripMetrics?.occupancyRatePercent || 0;
  document.getElementById('statOccupancy').textContent = `${occ}%`;
  document.getElementById('statOccupancyBar').style.width = `${Math.min(occ, 100)}%`;

  document.getElementById('statCodUncollected').textContent = formatVND(financials?.uncollectedCodAmount || 0);
  document.getElementById('statDepartedTrips').textContent = `${tripMetrics?.departedTrips || 0} chuyến`;
  document.getElementById('statNoShowCount').textContent = `${bookingMetrics?.noShowBookings || 0} đơn vi phạm`;
}

// Chart.js Visualizations
function renderDashboardCharts() {
  if (!appState.summary) return;

  // Chart 1: Bar Chart Revenue by Bus Company
  const ctxRevenue = document.getElementById('revenueBarChart');
  if (ctxRevenue) {
    if (revenueChart) revenueChart.destroy();

    const companies = appState.summary.companyBreakdown || [];
    const labels = companies.map(c => c.name || `Nhà xe #${c.companyId}`);
    const netData = companies.map(c => c.netRevenue || 0);
    const codData = companies.map(c => c.uncollectedCod || 0);

    revenueChart = new Chart(ctxRevenue, {
      type: 'bar',
      data: {
        labels: labels.length ? labels : ['Chưa có dữ liệu'],
        datasets: [
          {
            label: 'Thực thu ròng (VNPay + COD đã thu)',
            data: netData.length ? netData : [0],
            backgroundColor: '#0284c7',
            borderRadius: 8
          },
          {
            label: 'COD chưa thu (Tại bến)',
            data: codData.length ? codData : [0],
            backgroundColor: '#fbbf24',
            borderRadius: 8
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { position: 'top', labels: { boxWidth: 12, font: { family: 'Be Vietnam Pro', size: 11 } } },
          tooltip: {
            callbacks: {
              label: (ctx) => `${ctx.dataset.label}: ${formatVND(ctx.raw)}`
            }
          }
        },
        scales: {
          x: { grid: { display: false } },
          y: {
            ticks: {
              callback: (val) => val >= 1000000 ? `${(val / 1000000).toFixed(1)} tr` : `${(val / 1000).toFixed(0)} k`
            }
          }
        }
      }
    });
  }

  // Chart 2: Donut Chart Ticket & Payment Structure
  const ctxTicket = document.getElementById('ticketDonutChart');
  if (ctxTicket) {
    if (ticketChart) ticketChart.destroy();

    const bm = appState.summary.bookingMetrics || {};
    const confirmed = bm.confirmedBookings || 0;
    const cancelled = bm.cancelledBookings || 0;
    const noshow = bm.noShowBookings || 0;

    ticketChart = new Chart(ctxTicket, {
      type: 'doughnut',
      data: {
        labels: ['Xác nhận (Thành công)', 'Đã Hủy / Hoàn', 'Vắng mặt (No-Show)'],
        datasets: [{
          data: [confirmed || 1, cancelled, noshow],
          backgroundColor: ['#0284c7', '#ef4444', '#a855f7'],
          borderWidth: 2,
          borderColor: '#ffffff'
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { position: 'bottom', labels: { boxWidth: 10, font: { family: 'Be Vietnam Pro', size: 10 } } }
        },
        cutout: '72%'
      }
    });
  }
}

// Render Company Breakdown Table on Dashboard
function renderCompanyBreakdownTable() {
  const tbody = document.getElementById('companyBreakdownTbody');
  if (!tbody || !appState.summary) return;

  const list = appState.summary.companyBreakdown || [];
  if (list.length === 0) {
    tbody.innerHTML = `<tr><td colspan="8" class="text-center py-4 text-slate-400">Chưa có thông tin đối soát nhà xe.</td></tr>`;
    return;
  }

  tbody.innerHTML = list.map(c => `
    <tr class="hover:bg-sky-50/40 transition">
      <td class="py-3 px-4 font-bold text-slate-900">${c.name}</td>
      <td class="py-3 px-4">
        <span class="badge ${c.status === 'Active' ? 'badge-paid' : 'badge-cancelled'}">
          ${c.status === 'Active' ? 'Đang Hoạt Động' : c.status}
        </span>
      </td>
      <td class="py-3 px-4 text-center font-semibold">${c.bookingsCount}</td>
      <td class="py-3 px-4 text-right font-medium text-slate-700">${formatVND(c.collectedGross)}</td>
      <td class="py-3 px-4 text-right font-semibold text-amber-600">${formatVND(c.uncollectedCod)}</td>
      <td class="py-3 px-4 text-right font-medium text-rose-600">${formatVND(c.refundedAmount)}</td>
      <td class="py-3 px-4 text-right font-extrabold text-emerald-700">${formatVND(c.netRevenue)}</td>
      <td class="py-3 px-4 text-center">
        <button onclick="exportReconciliationCsv()" class="px-2 py-1 text-[11px] rounded bg-sky-50 text-sky-700 hover:bg-sky-100 font-semibold border border-sky-200">
          Đối soát
        </button>
      </td>
    </tr>
  `).join('');
}

// TAB 2: TRIPS TABLE
function renderTripsTable() {
  const tbody = document.getElementById('tripsTableTbody');
  if (!tbody) return;

  const search = (document.getElementById('tripSearchInput')?.value || '').toLowerCase();
  const filter = document.getElementById('tripStatusFilter')?.value || 'ALL';

  let list = appState.trips || [];
  if (search) {
    list = list.filter(t => 
      (t.tripCode && t.tripCode.toLowerCase().includes(search)) ||
      (t.routeName && t.routeName.toLowerCase().includes(search)) ||
      (t.plateNumber && t.plateNumber.toLowerCase().includes(search)) ||
      (t.companyName && t.companyName.toLowerCase().includes(search))
    );
  }
  if (filter !== 'ALL') {
    list = list.filter(t => t.status === filter);
  }

  if (list.length === 0) {
    tbody.innerHTML = `<tr><td colspan="9" class="text-center py-6 text-slate-400">Không tìm thấy chuyến xe nào phù hợp.</td></tr>`;
    return;
  }

  tbody.innerHTML = list.map(t => {
    const statusBadges = {
      Scheduled: 'badge-scheduled',
      Boarding: 'badge-boarding',
      Departed: 'badge-departed',
      Arrived: 'badge-arrived',
      Delayed: 'badge-delayed',
      Cancelled: 'badge-cancelled'
    };
    const badgeClass = statusBadges[t.status] || 'badge-scheduled';

    return `
      <tr class="hover:bg-slate-50 transition">
        <td class="py-3 px-4 font-bold text-sky-700">${t.tripCode || `TRIP-${t.tripId}`}</td>
        <td class="py-3 px-4">
          <div class="font-semibold text-slate-900">${t.routeName || 'Chưa đặt tên'}</div>
          <div class="text-[11px] text-slate-500">${t.companyName || ''}</div>
        </td>
        <td class="py-3 px-4 font-mono text-[11px]">${formatDateTime(t.departureAt)}</td>
        <td class="py-3 px-4">
          <div class="font-bold text-slate-800">${t.plateNumber || 'Chưa gán'}</div>
          <div class="text-[10px] text-slate-400">${t.busType || ''}</div>
        </td>
        <td class="py-3 px-4 font-medium text-slate-700">${t.driverName || 'Chưa phân công'}</td>
        <td class="py-3 px-4 text-right font-bold text-slate-900">${formatVND(t.basePrice)}</td>
        <td class="py-3 px-4 text-center">
          <span class="font-bold text-sky-700">${t.bookedSeatsCount || 0}</span> / ${t.totalSeats || 34}
        </td>
        <td class="py-3 px-4 text-center">
          <span class="badge ${badgeClass}">${t.status}</span>
        </td>
        <td class="py-3 px-4 text-center space-x-1">
          ${t.status !== 'Cancelled' ? `
            <button onclick="cancelTrip(${t.tripId})" title="Hủy chuyến & Hoàn tiền (AT11)" class="p-1 rounded text-rose-600 hover:bg-rose-50 transition">
              <i data-lucide="x-circle" class="w-4 h-4"></i>
            </button>
          ` : '<span class="text-[11px] text-slate-400">Đã đóng</span>'}
        </td>
      </tr>
    `;
  }).join('');
  lucide.createIcons();
}

// Cancel Trip Action (AT11)
async function cancelTrip(tripId) {
  const reason = prompt('Nhập lý do hủy chuyến (Hệ thống sẽ tự động ngừng bán vé, gửi thông báo và sinh yêu cầu hoàn tiền 100% cho hành khách):', 'Thời tiết xấu / Trục trặc kỹ thuật');
  if (!reason) return;

  try {
    const res = await api(`/api/operator/trips/${tripId}/cancel`, {
      method: 'POST',
      body: JSON.stringify({ reason })
    });
    showToast(res.message || 'Đã hủy chuyến thành công!');
    await loadAllData();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

// TAB 3: BOOKINGS TABLE
function renderBookingsTable() {
  const tbody = document.getElementById('bookingsTableTbody');
  if (!tbody) return;

  const search = (document.getElementById('bookingSearchInput')?.value || '').toLowerCase();
  const filter = document.getElementById('bookingPaymentFilter')?.value || 'ALL';

  let list = appState.bookings || [];
  if (search) {
    list = list.filter(b => 
      (b.bookingCode && b.bookingCode.toLowerCase().includes(search)) ||
      (b.contactName && b.contactName.toLowerCase().includes(search)) ||
      (b.contactPhone && b.contactPhone.toLowerCase().includes(search))
    );
  }

  if (filter === 'COD_UNPAID') {
    list = list.filter(b => b.payments && b.payments.some(p => p.method === 'COD' && p.status === 'Unpaid'));
  } else if (filter === 'PAID') {
    list = list.filter(b => b.payments && b.payments.some(p => p.status === 'Paid'));
  } else if (filter === 'REFUNDED') {
    list = list.filter(b => b.status === 'Refunded' || b.status === 'Cancelled');
  }

  if (list.length === 0) {
    tbody.innerHTML = `<tr><td colspan="9" class="text-center py-6 text-slate-400">Không có đơn đặt chỗ nào phù hợp.</td></tr>`;
    return;
  }

  tbody.innerHTML = list.map(b => {
    const pay = (b.payments && b.payments[0]) || {};
    const seats = b.details ? b.details.map(d => d.seatCode).join(', ') : (b.seatCodes || '--');
    const isCodUnpaid = pay.method === 'COD' && pay.status === 'Unpaid';

    return `
      <tr class="hover:bg-slate-50 transition">
        <td class="py-3 px-4 font-bold text-sky-700">${b.bookingCode}</td>
        <td class="py-3 px-4">
          <div class="font-bold text-slate-900">${b.contactName}</div>
          <div class="text-[11px] text-slate-500 font-mono">${b.contactPhone}</div>
        </td>
        <td class="py-3 px-4">
          <div class="font-semibold text-slate-800">${b.trip?.route?.name || 'Tuyến xe'}</div>
          <div class="text-[10px] text-slate-400">${formatDateTime(b.createdAt)}</div>
        </td>
        <td class="py-3 px-4 text-center font-bold text-sky-700">${seats}</td>
        <td class="py-3 px-4 text-right font-extrabold text-slate-900">${formatVND(b.totalAmount)}</td>
        <td class="py-3 px-4 text-center font-semibold text-slate-600">${pay.method || 'VNPay'}</td>
        <td class="py-3 px-4 text-center">
          <span class="badge ${pay.status === 'Paid' ? 'badge-paid' : pay.status === 'Unpaid' ? 'badge-unpaid' : 'badge-cancelled'}">
            ${pay.status || 'Unpaid'}
          </span>
        </td>
        <td class="py-3 px-4 text-center">
          <span class="badge ${b.status === 'Confirmed' ? 'badge-confirmed' : b.status === 'NoShow' ? 'badge-noshow' : 'badge-scheduled'}">
            ${b.status}
          </span>
        </td>
        <td class="py-3 px-4 text-center space-x-1">
          ${isCodUnpaid ? `
            <button onclick="collectCod(${b.bookingId})" title="Xác nhận đã thu COD" class="px-2.5 py-1 text-[11px] rounded-lg bg-emerald-600 text-white hover:bg-emerald-700 font-semibold shadow-xs">
              Thu COD
            </button>
          ` : ''}
          ${b.status === 'Confirmed' ? `
            <button onclick="markNoShow(${b.bookingId})" title="Đánh dấu khách không đến (No-Show)" class="px-2 py-1 text-[11px] rounded-lg border border-purple-200 text-purple-700 hover:bg-purple-50 font-semibold">
              No-Show
            </button>
          ` : ''}
        </td>
      </tr>
    `;
  }).join('');
  lucide.createIcons();
}

// Collect COD Action (AT08)
async function collectCod(bookingId) {
  if (!confirm('Xác nhận đã thu đủ tiền mặt COD từ hành khách?')) return;
  try {
    const res = await api(`/api/operator/bookings/${bookingId}/collect-cod`, { method: 'POST' });
    showToast(res.message || 'Đã xác nhận thu COD thành công!');
    await loadAllData();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

// Mark No-Show Action (Section 5.10)
async function markNoShow(bookingId) {
  if (!confirm('Đánh dấu hành khách này vắng mặt (No-Show)? Số lần vi phạm sẽ được ghi nhận vào tài khoản khách.')) return;
  try {
    const res = await api(`/api/operator/bookings/${bookingId}/mark-noshow`, { method: 'POST' });
    showToast(res.message || 'Đã đánh dấu No-Show thành công!');
    await loadAllData();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

// TAB 4: POS COUNTER STATION
function setupPosCounter() {
  const select = document.getElementById('posTripSelect');
  if (!select) return;

  const validTrips = appState.trips.filter(t => t.status === 'Scheduled' || t.status === 'Boarding');
  select.innerHTML = '<option value="">-- Chọn chuyến xe xuất bến --</option>' + 
    validTrips.map(t => `<option value="${t.tripId}">${t.tripCode || `TRIP-${t.tripId}`} | ${t.routeName} (${formatDateTime(t.departureAt)}) - ${formatVND(t.basePrice)}</option>`).join('');
}

function handlePosTripChange() {
  const tripId = document.getElementById('posTripSelect').value;
  if (!tripId) return;
  const trip = appState.trips.find(t => t.tripId == tripId);
  if (trip && trip.basePrice) {
    document.getElementById('posSeatCodes').placeholder = 'Vd: A01, A02';
  }
}

async function submitPosBooking() {
  const tripId = parseInt(document.getElementById('posTripSelect').value);
  const name = document.getElementById('posCustomerName').value.trim();
  const phone = document.getElementById('posCustomerPhone').value.trim();
  const seatsInput = document.getElementById('posSeatCodes').value.trim();
  const paymentMethod = document.getElementById('posPaymentMethod').value;

  if (!tripId || !name || !phone || !seatsInput) {
    showToast('Vui lòng điền đầy đủ chuyến xe, họ tên, SĐT và ghế ngồi.', 'error');
    return;
  }

  const seatCodes = seatsInput.split(',').map(s => s.trim().toUpperCase()).filter(Boolean);

  try {
    const res = await api('/api/operator/pos-booking', {
      method: 'POST',
      body: JSON.stringify({
        tripId,
        customerName: name,
        customerPhone: phone,
        seatCodes,
        paymentMethod
      })
    });

    showToast(`Đã xuất vé POS thành công! Mã đơn: ${res.booking?.bookingCode || 'OK'}`);
    
    // Update preview card
    document.getElementById('posLastTicketCard').innerHTML = `
      <div class="text-left space-y-1.5">
        <div class="flex justify-between items-center pb-2 border-b border-slate-200">
          <span class="font-bold text-sky-700">${res.booking?.bookingCode || 'VE-POS'}</span>
          <span class="badge badge-paid">ĐÃ THU TIỀN</span>
        </div>
        <p><strong>Khách hàng:</strong> ${name} - ${phone}</p>
        <p><strong>Chuyến xe:</strong> #${tripId}</p>
        <p><strong>Ghế:</strong> <span class="font-bold text-sky-800">${seatCodes.join(', ')}</span></p>
        <p><strong>Tổng tiền:</strong> <span class="font-bold text-emerald-700">${formatVND(res.booking?.totalAmount || 0)}</span></p>
      </div>
    `;

    clearPosForm();
    await loadAllData();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

function clearPosForm() {
  document.getElementById('posCustomerName').value = '';
  document.getElementById('posCustomerPhone').value = '';
  document.getElementById('posSeatCodes').value = '';
}

// TAB INSPECTOR: SOÁT VÉ QR & CHECK-IN TẠI BẾN
async function inspectWebTicket() {
  const input = document.getElementById('inspectorCodeInput');
  const code = (input?.value || '').trim();
  if (!code) {
    showToast('Vui lòng nhập mã vé hoặc mã QR cần soát.', 'error');
    return;
  }

  const container = document.getElementById('inspectorResultContainer');
  if (container) {
    container.innerHTML = `<div class="py-8 text-center text-slate-500"><i data-lucide="loader" class="w-8 h-8 mx-auto mb-2 animate-spin text-sky-600"></i>Đang kiểm tra vé...</div>`;
    lucide.createIcons();
  }

  try {
    const ticket = await api('/api/tickets/inspect', {
      method: 'POST',
      body: JSON.stringify({ qrOrTicketCode: code })
    });
    renderInspectorResult(ticket);
  } catch (err) {
    if (container) {
      container.innerHTML = `
        <div class="bg-rose-50 border border-rose-200 text-rose-800 p-6 rounded-2xl text-center space-y-2">
          <i data-lucide="alert-triangle" class="w-10 h-10 text-rose-600 mx-auto"></i>
          <h4 class="font-extrabold text-sm">Không Tìm Thấy Vé</h4>
          <p class="text-xs text-rose-700">${err.message}</p>
        </div>
      `;
      lucide.createIcons();
    }
  }
}

function inspectQuickCode(code) {
  const input = document.getElementById('inspectorCodeInput');
  if (input) input.value = code;
  inspectWebTicket();
}

function clearInspector() {
  const input = document.getElementById('inspectorCodeInput');
  if (input) input.value = '';
  const container = document.getElementById('inspectorResultContainer');
  if (container) {
    container.innerHTML = `
      <i data-lucide="scan-line" class="w-12 h-12 text-slate-300 mx-auto mb-3"></i>
      Vui lòng quét hoặc nhập mã vé QR để kiểm tra tình trạng thanh toán và lên xe.
    `;
    lucide.createIcons();
  }
}

function renderInspectorResult(t) {
  const container = document.getElementById('inspectorResultContainer');
  if (!container) return;

  const isBoarded = t.isBoarded === true || t.ticketStatus === 'Used';
  const isPaid = t.isPaid === true || t.paymentStatus === 'Paid';
  const isCodUnpaid = t.isCodUnpaid === true;
  const totalAmount = t.totalAmount || 0;
  const codAmount = t.codAmountToCollect || totalAmount;

  container.innerHTML = `
    <div class="space-y-4 text-left animate-fade-in">
      <!-- 1. TÌNH TRẠNG LÊN XE BANNER -->
      <div class="p-4 rounded-xl flex items-center space-x-3 text-white ${isBoarded ? 'bg-rose-600' : 'bg-emerald-600'} shadow-md">
        <i data-lucide="${isBoarded ? 'alert-octagon' : 'check-circle-2'}" class="w-8 h-8 flex-shrink-0"></i>
        <div>
          <h4 class="font-extrabold text-sm uppercase tracking-wide">
            ${isBoarded ? 'CẢNH BÁO: HÀNH KHÁCH NÀY ĐÃ LÊN XE TRƯỚC ĐÓ!' : 'HỢP LỆ: CHƯA LÊN XE'}
          </h4>
          <p class="text-xs text-white/90">
            ${isBoarded ? `Vé đã check-in lúc ${formatDateTime(t.boardedAt)}. TỪ CHỐI CHO LÊN XE LẶP LẠI (AT09)!` : 'Vé hợp lệ, sẵn sàng xác nhận cho khách lên xe.'}
          </p>
        </div>
      </div>

      <!-- 2. TÌNH TRẠNG TIỀN VÉ -->
      <div class="p-4 rounded-xl border-2 flex items-center space-x-3 ${isCodUnpaid ? 'bg-amber-50 border-amber-300 text-amber-900' : 'bg-emerald-50 border-emerald-300 text-emerald-900'}">
        <div class="w-10 h-10 rounded-full flex items-center justify-center flex-shrink-0 ${isCodUnpaid ? 'bg-amber-100 text-amber-700' : 'bg-emerald-100 text-emerald-700'}">
          <i data-lucide="${isCodUnpaid ? 'banknote' : 'badge-check'}" class="w-6 h-6"></i>
        </div>
        <div class="flex-1">
          <div class="font-bold text-xs uppercase">
            ${isCodUnpaid ? '⚠️ CHƯA THU TIỀN! CẦN THU COD TẠI CHỖ:' : '✅ ĐÃ THANH TOÁN ĐỦ QUA VNPAY / CHUYỂN KHOẢN'}
          </div>
          <div class="text-base font-black ${isCodUnpaid ? 'text-rose-600' : 'text-emerald-700'}">
            ${isCodUnpaid ? `${formatVND(codAmount)} TIỀN MẶT` : `Đã thu: ${formatVND(totalAmount)} (KHÔNG THU TIỀN CỦA KHÁCH)`}
          </div>
        </div>
      </div>

      <!-- 3. THÔNG TIN HÀNH KHÁCH & VỊ TRÍ GHẾ -->
      <div class="grid grid-cols-1 sm:grid-cols-3 gap-3 bg-slate-50 p-4 rounded-xl border border-slate-200">
        <div class="flex items-center space-x-3 sm:col-span-1">
          <div class="w-14 h-14 bg-sky-700 text-white rounded-xl flex flex-col items-center justify-center shadow-xs">
            <span class="text-[10px] font-bold text-sky-200 uppercase">GHẾ</span>
            <span class="text-lg font-black">${t.seatCode || '--'}</span>
          </div>
          <div>
            <div class="font-extrabold text-slate-900 text-sm">${t.passengerName || 'Khách hàng'}</div>
            <div class="text-xs text-slate-500 font-mono">${t.passengerPhone || '--'}</div>
            <div class="text-[11px] text-sky-700 font-mono font-semibold">${t.ticketCode || ''}</div>
          </div>
        </div>

        <div class="sm:col-span-2 text-xs space-y-1 text-slate-600 border-t sm:border-t-0 sm:border-l border-slate-200 pt-2 sm:pt-0 sm:pl-3">
          <div><strong class="text-slate-800">Tuyến xe:</strong> ${t.routeName || '--'}</div>
          <div><strong class="text-slate-800">Phương tiện:</strong> ${t.plateNumber || '--'} (${t.busType || ''})</div>
          <div><strong class="text-slate-800">Giờ khởi hành:</strong> ${formatDateTime(t.departureAt)}</div>
          <div><strong class="text-slate-800">Đón / Trả:</strong> ${t.pickupStop || 'Bến xe'} ➔ ${t.dropoffStop || 'Bến xe'}</div>
        </div>
      </div>

      <!-- 4. NÚT HÀNH ĐỘNG DÀNH CHO NHÂN VIÊN -->
      <div class="pt-2 flex flex-wrap gap-2 justify-end">
        ${!isBoarded ? (
          isCodUnpaid ? `
            <button onclick="confirmWebCheckIn('${t.ticketCode}', true)" class="px-5 py-2.5 rounded-xl bg-amber-600 hover:bg-amber-700 text-white font-extrabold text-xs shadow-md shadow-amber-600/20 flex items-center transition">
              <i data-lucide="banknote" class="w-4 h-4 mr-1.5"></i> XÁC NHẬN ĐÃ THU ${formatVND(codAmount)} COD & CHO LÊN XE
            </button>
          ` : `
            <button onclick="confirmWebCheckIn('${t.ticketCode}', false)" class="px-5 py-2.5 rounded-xl bg-emerald-600 hover:bg-emerald-700 text-white font-extrabold text-xs shadow-md shadow-emerald-600/20 flex items-center transition">
              <i data-lucide="check-check" class="w-4 h-4 mr-1.5"></i> XÁC NHẬN CHO KHÁCH LÊN XE (CHECK-IN)
            </button>
          `
        ) : `
          <div class="text-xs text-rose-600 font-bold bg-rose-50 px-3 py-2 rounded-lg border border-rose-200 flex items-center">
            <i data-lucide="x-circle" class="w-4 h-4 mr-1.5"></i> VÉ ĐÃ CHECK-IN LÊN XE RỒI - TỪ CHỐI CHO LÊN XE LẶP LẠI
          </div>
        `}
      </div>
    </div>
  `;
  lucide.createIcons();
}

async function confirmWebCheckIn(ticketCode, collectCod) {
  try {
    const res = await api('/api/tickets/check-in', {
      method: 'POST',
      body: JSON.stringify({
        qrOrTicketCode: ticketCode,
        collectCodNow: collectCod,
        deviceInfo: 'Cổng Web Soát Vé Bến Xe'
      })
    });
    showToast(res.message || 'Xác nhận lên xe thành công!');
    inspectQuickCode(ticketCode);
    await loadAllData();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

// TAB 5: BUSES (Đội xe)
function renderBuses() {
  const grid = document.getElementById('busesGrid');
  if (!grid) return;

  const list = appState.buses || [];
  if (list.length === 0) {
    grid.innerHTML = `<div class="col-span-full text-center py-8 text-slate-400">Chưa có phương tiện nào trong đội xe.</div>`;
    return;
  }

  grid.innerHTML = list.map(b => `
    <div class="glass-card p-5 rounded-2xl flex flex-col justify-between">
      <div>
        <div class="flex items-center justify-between mb-3">
          <span class="badge ${b.status === 'Active' ? 'badge-paid' : 'badge-cancelled'}">
            ${b.status === 'Active' ? 'Hoạt Động' : b.status}
          </span>
          <span class="text-xs font-mono font-bold text-slate-500">ID: #${b.busId}</span>
        </div>
        <div class="flex items-center space-x-3 mb-3">
          <div class="w-10 h-10 rounded-xl bg-sky-100 text-sky-700 flex items-center justify-center font-bold">
            <i data-lucide="bus-front" class="w-6 h-6"></i>
          </div>
          <div>
            <h4 class="font-extrabold text-slate-900 text-base">${b.plateNumber}</h4>
            <p class="text-xs text-slate-500">${b.busType} • ${b.totalSeats} ghế</p>
          </div>
        </div>
      </div>
      <div class="pt-3 border-t border-slate-100 flex items-center justify-between text-xs text-slate-500">
        <span>Năm SX: ${b.manufacturingYear || 2024}</span>
        <span class="font-semibold text-sky-600">Sơ đồ chuẩn</span>
      </div>
    </div>
  `).join('');
  lucide.createIcons();
}

// TAB 6: ROUTES (Tuyến đường)
function renderRoutes() {
  const grid = document.getElementById('routesGrid');
  if (!grid) return;

  const list = appState.routes || [];
  if (list.length === 0) {
    grid.innerHTML = `<div class="col-span-full text-center py-8 text-slate-400">Chưa có tuyến đường nào.</div>`;
    return;
  }

  grid.innerHTML = list.map(r => `
    <div class="glass-panel p-5 rounded-2xl">
      <div class="flex items-center justify-between mb-2">
        <h4 class="font-bold text-slate-900 text-sm flex items-center">
          <i data-lucide="map-pin" class="w-4 h-4 mr-1.5 text-sky-600"></i> ${r.name}
        </h4>
        <span class="text-xs font-bold text-slate-600 bg-slate-100 px-2 py-0.5 rounded-lg">${r.distanceKm} km</span>
      </div>
      <p class="text-xs text-slate-500 mb-3">Thời gian dự kiến: ~${Math.round(r.estimatedDurationMinutes / 60)} giờ (${r.estimatedDurationMinutes} phút)</p>
      
      <!-- Stops list -->
      <div class="bg-slate-50/70 p-3 rounded-xl border border-slate-100 space-y-1.5 text-xs">
        <div class="font-semibold text-slate-700 text-[11px] uppercase tracking-wider mb-1">Trạm đón trả trên tuyến:</div>
        ${(r.stops || []).map(s => `
          <div class="flex justify-between items-center text-[11px]">
            <span class="text-slate-800 font-medium">• ${s.stopName}</span>
            <span class="text-slate-500 font-mono">+${s.offsetMinutes}p ${s.surcharge > 0 ? `(+${formatVND(s.surcharge)})` : ''}</span>
          </div>
        `).join('')}
      </div>
    </div>
  `).join('');
  lucide.createIcons();
}

// TAB 7: DRIVERS TABLE
function renderDrivers() {
  const tbody = document.getElementById('driversTableTbody');
  if (!tbody) return;

  const list = appState.drivers || [];
  if (list.length === 0) {
    tbody.innerHTML = `<tr><td colspan="7" class="text-center py-6 text-slate-400">Chưa có thông tin tài xế.</td></tr>`;
    return;
  }

  tbody.innerHTML = list.map(d => {
    const isExpired = d.licenseExpiry && new Date(d.licenseExpiry) < new Date();
    return `
      <tr class="hover:bg-slate-50 transition">
        <td class="py-3 px-4 font-mono font-bold text-slate-500">TX-${d.driverId}</td>
        <td class="py-3 px-4 font-bold text-slate-900">${d.fullName}</td>
        <td class="py-3 px-4 font-mono text-slate-600">${d.phone}</td>
        <td class="py-3 px-4 font-mono font-medium">${d.licenseNumber}</td>
        <td class="py-3 px-4 text-center font-bold text-sky-700">${d.licenseClass}</td>
        <td class="py-3 px-4 font-mono text-xs ${isExpired ? 'text-rose-600 font-bold' : 'text-slate-600'}">
          ${d.licenseExpiry ? d.licenseExpiry.substring(0, 10) : '--'}
          ${isExpired ? '<span class="text-[10px] ml-1 bg-rose-100 text-rose-700 px-1 py-0.5 rounded">Hết hạn</span>' : ''}
        </td>
        <td class="py-3 px-4 text-center">
          <span class="badge ${d.status === 'Active' ? 'badge-paid' : 'badge-scheduled'}">
            ${d.status === 'Active' ? 'Sẵn Sàng' : d.status}
          </span>
        </td>
      </tr>
    `;
  }).join('');
}

// TAB 8: PARCELS TABLE
function renderParcels() {
  const tbody = document.getElementById('parcelsTableTbody');
  if (!tbody) return;

  const list = appState.parcels || [];
  if (list.length === 0) {
    tbody.innerHTML = `<tr><td colspan="8" class="text-center py-6 text-slate-400">Chưa có kiện hàng ký gửi nào.</td></tr>`;
    return;
  }

  tbody.innerHTML = list.map(p => `
    <tr class="hover:bg-slate-50 transition">
      <td class="py-3 px-4 font-mono font-bold text-sky-700">${p.trackingCode || `VD-${p.parcelId}`}</td>
      <td class="py-3 px-4">
        <div class="font-bold text-slate-900">${p.senderName}</div>
        <div class="text-[11px] text-slate-500 font-mono">${p.senderPhone}</div>
      </td>
      <td class="py-3 px-4">
        <div class="font-bold text-slate-900">${p.receiverName}</div>
        <div class="text-[11px] text-slate-500 font-mono">${p.receiverPhone}</div>
      </td>
      <td class="py-3 px-4 font-mono text-xs">Chuyến #${p.tripId}</td>
      <td class="py-3 px-4 text-center font-bold">${p.weightKg} kg</td>
      <td class="py-3 px-4 text-right font-extrabold text-slate-900">${formatVND(p.fee)}</td>
      <td class="py-3 px-4 text-center">
        <span class="badge badge-paid">${p.status || 'Received'}</span>
      </td>
      <td class="py-3 px-4 text-center">
        <button onclick="updateParcelStatus(${p.parcelId}, 'Delivered')" class="px-2 py-1 text-[11px] rounded bg-emerald-50 text-emerald-700 hover:bg-emerald-100 font-semibold border border-emerald-200">
          Đã Giao
        </button>
      </td>
    </tr>
  `).join('');
}

async function updateParcelStatus(parcelId, status) {
  try {
    await api(`/api/operator/parcels/${parcelId}/status`, {
      method: 'POST',
      body: JSON.stringify({ status })
    });
    showToast('Đã cập nhật trạng thái kiện hàng!');
    await loadAllData();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

// TAB 9: ADMIN COMPANIES
function renderCompanies() {
  const tbody = document.getElementById('companiesTableTbody');
  if (!tbody) return;

  const list = appState.companies || [];
  if (list.length === 0) {
    tbody.innerHTML = `<tr><td colspan="7" class="text-center py-6 text-slate-400">Không có dữ liệu nhà xe.</td></tr>`;
    return;
  }

  tbody.innerHTML = list.map(c => `
    <tr class="hover:bg-slate-50 transition">
      <td class="py-3 px-4 font-mono font-bold text-slate-500">${c.companyId}</td>
      <td class="py-3 px-4 font-bold text-slate-900">${c.name}</td>
      <td class="py-3 px-4 font-mono font-semibold">${c.taxCode}</td>
      <td class="py-3 px-4 text-slate-600">${c.phone || ''} • ${c.email || ''}</td>
      <td class="py-3 px-4 text-center">
        <span class="badge ${c.status === 'Active' ? 'badge-paid' : c.status === 'Pending' ? 'badge-boarding' : 'badge-cancelled'}">
          ${c.status}
        </span>
      </td>
      <td class="py-3 px-4 font-mono text-[11px]">${formatDateTime(c.createdAt)}</td>
      <td class="py-3 px-4 text-center space-x-1">
        ${c.status === 'Pending' ? `
          <button onclick="updateCompanyStatus(${c.companyId}, 'Active')" class="px-2.5 py-1 text-[11px] rounded bg-emerald-600 text-white font-semibold shadow-xs">
            Duyệt
          </button>
          <button onclick="updateCompanyStatus(${c.companyId}, 'Rejected')" class="px-2 py-1 text-[11px] rounded bg-rose-50 text-rose-700 font-semibold border border-rose-200">
            Từ Chối
          </button>
        ` : c.status === 'Active' ? `
          <button onclick="updateCompanyStatus(${c.companyId}, 'Suspended')" class="px-2 py-1 text-[11px] rounded bg-amber-50 text-amber-700 font-semibold border border-amber-200">
            Đình Chỉ
          </button>
        ` : `
          <button onclick="updateCompanyStatus(${c.companyId}, 'Active')" class="px-2 py-1 text-[11px] rounded bg-sky-50 text-sky-700 font-semibold border border-sky-200">
            Kích Hoạt Lại
          </button>
        `}
      </td>
    </tr>
  `).join('');
}

async function updateCompanyStatus(companyId, status) {
  const reason = prompt(`Nhập lý do chuyển trạng thái sang '${status}':`, status === 'Active' ? 'Hồ sơ đầy đủ hợp lệ' : 'Vi phạm quy định');
  if (reason === null) return;

  try {
    const res = await api(`/api/admin/companies/${companyId}/status`, {
      method: 'POST',
      body: JSON.stringify({ status, reason })
    });
    showToast(res.message || 'Cập nhật trạng thái nhà xe thành công!');
    await loadAllData();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

// TAB 10: ADMIN USERS
function renderUsers() {
  const tbody = document.getElementById('usersTableTbody');
  if (!tbody) return;

  const list = appState.users || [];
  if (list.length === 0) {
    tbody.innerHTML = `<tr><td colspan="8" class="text-center py-6 text-slate-400">Không có dữ liệu người dùng.</td></tr>`;
    return;
  }

  tbody.innerHTML = list.map(u => `
    <tr class="hover:bg-slate-50 transition">
      <td class="py-3 px-4 font-mono font-bold text-slate-500">${u.userId}</td>
      <td class="py-3 px-4 font-bold text-slate-900">${u.fullName}</td>
      <td class="py-3 px-4 font-mono text-slate-600">${u.email}</td>
      <td class="py-3 px-4 font-mono text-slate-600">${u.phone || '--'}</td>
      <td class="py-3 px-4">
        ${(u.roles || []).map(r => `<span class="badge badge-confirmed mr-1 text-[10px]">${r}</span>`).join('')}
      </td>
      <td class="py-3 px-4 text-center font-bold ${u.noShowCount >= 2 ? 'text-rose-600' : 'text-slate-600'}">
        ${u.noShowCount}
      </td>
      <td class="py-3 px-4 text-center">
        <span class="badge ${u.isActive ? 'badge-paid' : 'badge-cancelled'}">
          ${u.isActive ? 'Hoạt Động' : 'Đã Khóa'}
        </span>
      </td>
      <td class="py-3 px-4 text-center space-x-1">
        <button onclick="toggleUserActive(${u.userId})" class="px-2 py-1 text-[11px] rounded ${u.isActive ? 'bg-rose-50 text-rose-700 border border-rose-200' : 'bg-emerald-50 text-emerald-700 border border-emerald-200'} font-semibold">
          ${u.isActive ? 'Khóa' : 'Mở Khóa'}
        </button>
        ${u.noShowCount > 0 ? `
          <button onclick="resetUserNoShow(${u.userId})" title="Xóa phạt No-Show mở lại COD (Section 5.10)" class="px-2 py-1 text-[11px] rounded bg-purple-50 text-purple-700 border border-purple-200 font-semibold">
            Xóa No-Show
          </button>
        ` : ''}
      </td>
    </tr>
  `).join('');
}

async function toggleUserActive(userId) {
  try {
    const res = await api(`/api/admin/users/${userId}/toggle-active`, { method: 'POST' });
    showToast(res.message || 'Đã thay đổi trạng thái tài khoản!');
    await loadAllData();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

async function resetUserNoShow(userId) {
  try {
    const res = await api(`/api/admin/users/${userId}/reset-noshow`, { method: 'POST' });
    showToast(res.message || 'Đã khôi phục quyền COD cho người dùng!');
    await loadAllData();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

// TAB 11: ADMIN REFUNDS
function renderRefunds() {
  const tbody = document.getElementById('refundsTableTbody');
  if (!tbody) return;

  const list = appState.refunds || [];
  if (list.length === 0) {
    tbody.innerHTML = `<tr><td colspan="8" class="text-center py-6 text-slate-400">Không có yêu cầu hoàn tiền nào.</td></tr>`;
    return;
  }

  tbody.innerHTML = list.map(r => `
    <tr class="hover:bg-slate-50 transition">
      <td class="py-3 px-4 font-mono font-bold text-slate-500">RF-${r.refundId}</td>
      <td class="py-3 px-4 font-mono font-bold text-sky-700">${r.bookingCode}</td>
      <td class="py-3 px-4 font-semibold text-slate-800">${r.companyName}</td>
      <td class="py-3 px-4 text-right font-extrabold text-rose-600">${formatVND(r.amount)}</td>
      <td class="py-3 px-4 text-slate-600 text-xs">${r.reason || 'Hủy vé'}</td>
      <td class="py-3 px-4 font-mono text-[11px]">${formatDateTime(r.requestedAt)}</td>
      <td class="py-3 px-4 text-center">
        <span class="badge ${r.status === 'Completed' ? 'badge-paid' : 'badge-unpaid'}">
          ${r.status}
        </span>
      </td>
      <td class="py-3 px-4 text-center">
        ${r.status === 'Pending' ? `
          <button onclick="completeRefund(${r.refundId})" class="px-2.5 py-1 text-[11px] rounded bg-emerald-600 text-white font-semibold shadow-xs">
            Hoàn Tất
          </button>
        ` : '<span class="text-slate-400 text-xs">Đã xong</span>'}
      </td>
    </tr>
  `).join('');
}

async function completeRefund(refundId) {
  if (!confirm('Xác nhận hoàn tất hoàn tiền cho khách qua cổng thanh toán?')) return;
  try {
    const res = await api(`/api/admin/refunds/${refundId}/complete`, { method: 'POST' });
    showToast(res.message || 'Đã hoàn tất hoàn tiền!');
    await loadAllData();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

// TAB 12: ADMIN PROMOTIONS
function renderPromotions() {
  const grid = document.getElementById('promotionsGrid');
  if (!grid) return;

  const list = appState.promotions || [];
  if (list.length === 0) {
    grid.innerHTML = `<div class="col-span-full text-center py-8 text-slate-400">Chưa có mã khuyến mãi nào.</div>`;
    return;
  }

  grid.innerHTML = list.map(p => `
    <div class="glass-card p-5 rounded-2xl flex flex-col justify-between">
      <div>
        <div class="flex items-center justify-between mb-2">
          <span class="badge ${p.isActive ? 'badge-paid' : 'badge-cancelled'}">
            ${p.isActive ? 'Đang Áp Dụng' : 'Hết Hạn'}
          </span>
          <span class="text-xs text-slate-400 font-mono">Lượt dùng: ${p.usedCount || 0}/${p.usageLimit}</span>
        </div>
        <div class="my-2">
          <h4 class="text-lg font-black tracking-wider text-sky-800 uppercase font-mono">${p.code}</h4>
          <p class="text-xs text-slate-500 mt-1">${p.description || ''}</p>
        </div>
      </div>
      <div class="pt-3 border-t border-slate-100 flex items-center justify-between">
        <span class="text-xs font-bold text-emerald-700">
          Giảm: ${p.discountType === 'Percent' ? `${p.discountValue}%` : formatVND(p.discountValue)}
        </span>
        <span class="text-[11px] text-slate-400 font-mono">HSD: ${p.expiresAt ? p.expiresAt.substring(0, 10) : 'Vĩnh viễn'}</span>
      </div>
    </div>
  `).join('');
}

// TAB 13: ACCEPTANCE CRITERIA (AT01 - AT12)
function renderAcceptanceCriteria() {
  const grid = document.getElementById('acceptanceCriteriaGrid');
  if (!grid) return;

  const list = appState.acceptance || [];
  if (list.length === 0) {
    grid.innerHTML = `<div class="col-span-full text-center py-8 text-slate-400">Đang tải báo cáo kiểm định 12 tiêu chí...</div>`;
    return;
  }

  grid.innerHTML = list.map(c => `
    <div class="glass-panel p-5 rounded-2xl border-l-4 border-l-emerald-500">
      <div class="flex items-center justify-between mb-2">
        <div class="flex items-center space-x-2">
          <span class="font-black text-sm font-mono text-emerald-700">${c.code}</span>
          <h4 class="font-bold text-slate-900 text-xs sm:text-sm">${c.title}</h4>
        </div>
        <span class="badge badge-paid flex items-center">
          <i data-lucide="check" class="w-3 h-3 mr-1"></i> ĐẠT
        </span>
      </div>
      <p class="text-xs text-slate-600 bg-slate-50/80 p-3 rounded-xl border border-slate-100 font-mono text-[11px] leading-relaxed">
        ${c.evidence}
      </p>
    </div>
  `).join('');
  lucide.createIcons();
}

// TAB 14: AUDIT LOGS
function renderAuditLogs() {
  const tbody = document.getElementById('auditLogsTbody');
  if (!tbody) return;

  const list = appState.auditLogs || [];
  if (list.length === 0) {
    tbody.innerHTML = `<tr><td colspan="4" class="text-center py-6 text-slate-400">Chưa có nhật ký audit log nào.</td></tr>`;
    return;
  }

  tbody.innerHTML = list.map(log => `
    <tr class="hover:bg-slate-50">
      <td class="py-2.5 px-4 text-slate-500 whitespace-nowrap">${formatDateTime(log.createdAt)}</td>
      <td class="py-2.5 px-4 font-bold text-sky-700">${log.action}</td>
      <td class="py-2.5 px-4 text-slate-700">${log.entityName} #${log.entityId}</td>
      <td class="py-2.5 px-4 text-slate-600">${log.details || ''}</td>
    </tr>
  `).join('');
}

// Export CSV Report (Section 15, AT12)
async function exportReconciliationCsv() {
  try {
    const res = await api('/api/admin/reports/export-csv');
    if (!res.csvContent) throw new Error('Không có nội dung CSV.');

    const blob = new Blob([res.csvContent], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.setAttribute('download', res.fileName || 'DoiSoat_BusTicketBooking.csv');
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    showToast(`Đã tải xuống file đối soát (${res.totalRows} dòng)!`);
  } catch (err) {
    showToast(err.message, 'error');
  }
}

// Modal Form Submissions
function populateModalSelects(modalId) {
  if (modalId === 'addTripModal') {
    const routeSel = document.getElementById('newTripRouteId');
    const busSel = document.getElementById('newTripBusId');
    const driverSel = document.getElementById('newTripDriverId');

    if (routeSel) {
      routeSel.innerHTML = appState.routes.map(r => `<option value="${r.routeId}">${r.name} (${r.distanceKm}km)</option>`).join('');
    }
    if (busSel) {
      busSel.innerHTML = appState.buses.filter(b => b.status === 'Active').map(b => `<option value="${b.busId}">${b.plateNumber} (${b.busType} - ${b.totalSeats} chỗ)</option>`).join('');
    }
    if (driverSel) {
      driverSel.innerHTML = appState.drivers.filter(d => d.status === 'Active').map(d => `<option value="${d.driverId}">${d.fullName} (${d.licenseClass})</option>`).join('');
    }
    // Set default departure to tomorrow 08:00
    const now = new Date();
    now.setDate(now.getDate() + 1);
    now.setHours(8, 0, 0, 0);
    const departureInput = document.getElementById('newTripDeparture');
    if (departureInput) departureInput.value = now.toISOString().slice(0, 16);
  }

  if (modalId === 'bulkTripModal') {
    const routeSel = document.getElementById('bulkRouteId');
    const busSel = document.getElementById('bulkBusId');
    const driverSel = document.getElementById('bulkDriverId');
    if (routeSel) routeSel.innerHTML = appState.routes.map(r => `<option value="${r.routeId}">${r.name}</option>`).join('');
    if (busSel) busSel.innerHTML = appState.buses.filter(b => b.status === 'Active').map(b => `<option value="${b.busId}">${b.plateNumber}</option>`).join('');
    if (driverSel) driverSel.innerHTML = appState.drivers.filter(d => d.status === 'Active').map(d => `<option value="${d.driverId}">${d.fullName}</option>`).join('');
    const startInput = document.getElementById('bulkStartDate');
    if (startInput) startInput.value = new Date().toISOString().slice(0, 10);
  }

  if (modalId === 'addParcelModal') {
    const tripSel = document.getElementById('newParcelTripId');
    if (tripSel) {
      tripSel.innerHTML = appState.trips.filter(t => t.status === 'Scheduled' || t.status === 'Boarding').map(t => `<option value="${t.tripId}">${t.tripCode || `TRIP-${t.tripId}`} - ${t.routeName}</option>`).join('');
    }
  }

  if (modalId === 'addDriverModal') {
    const exp = document.getElementById('newDriverLicenseExpiry');
    if (exp) {
      const d = new Date();
      d.setFullYear(d.getFullYear() + 3);
      exp.value = d.toISOString().slice(0, 10);
    }
  }
}

async function handleAddTripSubmit(e) {
  e.preventDefault();
  const routeId = parseInt(document.getElementById('newTripRouteId').value);
  const busId = parseInt(document.getElementById('newTripBusId').value);
  const driverId = parseInt(document.getElementById('newTripDriverId').value);
  const departureAt = new Date(document.getElementById('newTripDeparture').value).toISOString();
  const basePrice = parseFloat(document.getElementById('newTripBasePrice').value);

  try {
    const res = await api('/api/operator/trips', {
      method: 'POST',
      body: JSON.stringify({ routeId, busId, driverId, departureAt, basePrice })
    });
    showToast(res.message || 'Đã tạo chuyến xe thành công!');
    closeModal('addTripModal');
    await loadAllData();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

async function handleBulkTripSubmit(e) {
  e.preventDefault();
  const routeId = parseInt(document.getElementById('bulkRouteId').value);
  const busId = parseInt(document.getElementById('bulkBusId').value);
  const driverId = parseInt(document.getElementById('bulkDriverId').value);
  const startDate = document.getElementById('bulkStartDate').value;
  const daysCount = parseInt(document.getElementById('bulkDaysCount').value);
  const timesStr = document.getElementById('bulkDepartureTimes').value;
  const departureTimes = timesStr.split(',').map(s => s.trim());
  const basePrice = parseFloat(document.getElementById('bulkBasePrice').value);

  try {
    const res = await api('/api/operator/trips/bulk-generate', {
      method: 'POST',
      body: JSON.stringify({ routeId, busId, driverId, startDate, daysCount, departureTimes, basePrice })
    });
    showToast(res.message || 'Đã lập lịch chuyến xe hàng loạt thành công!');
    closeModal('bulkTripModal');
    await loadAllData();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

async function handleAddBusSubmit(e) {
  e.preventDefault();
  const plateNumber = document.getElementById('newBusPlate').value.trim();
  const busType = document.getElementById('newBusType').value;
  const totalSeats = parseInt(document.getElementById('newBusSeats').value);

  try {
    const res = await api('/api/operator/buses', {
      method: 'POST',
      body: JSON.stringify({ plateNumber, busType, totalSeats, manufacturingYear: 2024 })
    });
    showToast(res.message || 'Đã lưu phương tiện mới vào đội xe!');
    closeModal('addBusModal');
    await loadAllData();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

async function handleAddRouteSubmit(e) {
  e.preventDefault();
  const name = document.getElementById('newRouteName').value.trim();
  const distanceKm = parseFloat(document.getElementById('newRouteDistance').value);
  const estimatedDurationMinutes = parseInt(document.getElementById('newRouteDuration').value);

  try {
    const res = await api('/api/operator/routes', {
      method: 'POST',
      body: JSON.stringify({ name, distanceKm, estimatedDurationMinutes, originProvinceId: 1, destinationProvinceId: 2 })
    });
    showToast(res.message || 'Đã tạo tuyến đường mới thành công!');
    closeModal('addRouteModal');
    await loadAllData();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

async function handleAddDriverSubmit(e) {
  e.preventDefault();
  const fullName = document.getElementById('newDriverName').value.trim();
  const phone = document.getElementById('newDriverPhone').value.trim();
  const licenseClass = document.getElementById('newDriverLicenseClass').value;
  const licenseNumber = document.getElementById('newDriverLicenseNumber').value.trim();
  const licenseExpiry = document.getElementById('newDriverLicenseExpiry').value;

  try {
    const res = await api('/api/operator/drivers', {
      method: 'POST',
      body: JSON.stringify({ fullName, phone, licenseClass, licenseNumber, licenseExpiry })
    });
    showToast(res.message || 'Đã tiếp nhận hồ sơ tài xế thành công!');
    closeModal('addDriverModal');
    await loadAllData();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

async function handleAddParcelSubmit(e) {
  e.preventDefault();
  const tripId = parseInt(document.getElementById('newParcelTripId').value);
  const senderName = document.getElementById('newParcelSenderName').value.trim();
  const senderPhone = document.getElementById('newParcelSenderPhone').value.trim();
  const receiverName = document.getElementById('newParcelReceiverName').value.trim();
  const receiverPhone = document.getElementById('newParcelReceiverPhone').value.trim();
  const weightKg = parseFloat(document.getElementById('newParcelWeight').value);
  const fee = parseFloat(document.getElementById('newParcelFee').value);

  try {
    const res = await api('/api/operator/parcels', {
      method: 'POST',
      body: JSON.stringify({ tripId, senderName, senderPhone, receiverName, receiverPhone, weightKg, fee })
    });
    showToast(res.message || 'Đã lập vận đơn ký gửi hàng thành công!');
    closeModal('addParcelModal');
    await loadAllData();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

async function handleAddPromoSubmit(e) {
  e.preventDefault();
  const code = document.getElementById('newPromoCode').value.trim().toUpperCase();
  const description = document.getElementById('newPromoDesc').value.trim();
  const discountType = document.getElementById('newPromoType').value;
  const discountValue = parseFloat(document.getElementById('newPromoValue').value);

  try {
    const res = await api('/api/admin/promotions', {
      method: 'POST',
      body: JSON.stringify({ code, description, discountType, discountValue, maxDiscountAmount: discountValue, usageLimit: 100 })
    });
    showToast(res.message || 'Đã tạo mã ưu đãi mới thành công!');
    closeModal('addPromoModal');
    await loadAllData();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

// Initial Bootstrap on Page Load
window.addEventListener('DOMContentLoaded', async () => {
  lucide.createIcons();
  if (token && currentUser) {
    updateUserUI();
    document.getElementById('loginModal').classList.add('hidden');
    await loadAllData();
  } else {
    // Show login modal by default
    document.getElementById('loginModal').classList.remove('hidden');
  }
});

