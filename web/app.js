// 장치 배치 순서 (2열 3행 그리드)
// 헤더: [강        단]
// 행1: [ f3-ac-03 ][ f3-ac-01 ]  강, 단
// 행2: [ f3-ac-04 ][ f3-ac-02 ]  강, 단
// 행3: [ f4-ac-01 ][ f4-ac-02 ]  강, 단
const DEVICE_GRID_ORDER = [
    ['f3-ac-01', 'f3-ac-03' ],  // 행1: 강, 단
    ['f3-ac-02', 'f3-ac-04' ],  // 행2: 강, 단
    ['f4-ac-01', 'f4-ac-02']   // 행3: 강, 단
];

// 장치 위치 설명
const DEVICE_LOCATIONS = {
    'f3-ac-01': '3층 악기 쪽',
    'f3-ac-02': '3층 악기 쪽(뒤)',
    'f3-ac-03': '3층 성가대 쪽',
    'f3-ac-04': '3층 성가대 쪽(뒤)',
    'f4-ac-01': '4층 악기 쪽',
    'f4-ac-02': '4층 성가대 쪽'
};

// 층수 정보
const DEVICE_FLOOR = {
    'f3-ac-01': '3층',
    'f3-ac-02': '3층',
    'f3-ac-03': '3층',
    'f3-ac-04': '3층',
    'f4-ac-01': '4층',
    'f4-ac-02': '4층'
};

// 전역 상태
let devices = [];
let deviceStatuses = {};
let selectedDeviceIds = []; // 여러 장치 선택 가능
let pendingDevices = new Set(); // 진행중인 장치 목록
const GLOBAL_ACTION_TIMEOUT_MS = 10000; // 전체 제어/적용 시 최대 대기 시간

// Health 상태 안정화를 위한 히스토리 관리
const healthHistory = {}; // { deviceId: { recent: [{healthy, timestamp}], stable: true/false, lastChangeTime } }
const HEALTH_HISTORY_SIZE = 10; // 최근 10개 상태 저장
const HEALTH_TO_UNHEALTHY_FAILURES = 5; // 연속 5번 실패해야 unhealthy로 변경 (약 25초)
const HEALTH_TO_HEALTHY_SUCCESSES = 6; // 연속 6번 성공해야 healthy로 변경 (약 30초)
const HEALTH_MIN_FAILURE_RATIO = 0.7; // 최근 히스토리 중 70% 이상 실패해야 unhealthy
const HEALTH_MIN_SUCCESS_RATIO = 0.8; // 최근 히스토리 중 80% 이상 성공해야 healthy

// 저장된 설정 불러오기
function loadSavedCommand() {
    try {
        const saved = localStorage.getItem('lastAcCommand');
        if (saved) {
            return JSON.parse(saved);
        }
    } catch (e) {
        console.error('Failed to load saved command:', e);
    }
    // 기본값
    return {
        power: 'on',
        mode: 'cool',
        temp: 24,
        fan: 'auto',
        swing: 'on',
    };
}

// 설정 저장하기
function saveCommand(command) {
    try {
        localStorage.setItem('lastAcCommand', JSON.stringify(command));
    } catch (e) {
        console.error('Failed to save command:', e);
    }
}

let currentCommand = loadSavedCommand();

// DOM 요소
const devicesGrid = document.getElementById('devicesGrid');
const controlPanel = document.getElementById('controlPanel');
const selectedDeviceText = document.getElementById('selectedDevice');
const allOnBtn = document.getElementById('allOnBtn');
const allOffBtn = document.getElementById('allOffBtn');
const applyBtn = document.getElementById('applyBtn');

function setActionButtonsDisabled(disabled) {
    try {
        if (allOnBtn) allOnBtn.disabled = disabled;
        if (allOffBtn) allOffBtn.disabled = disabled;
        if (applyBtn) applyBtn.disabled = disabled;
    } catch (e) {
        console.warn('setActionButtonsDisabled failed:', e);
    }
}

// 초기화
async function init() {
    // 저장된 설정으로 제어 패널 초기화
    updateControlPanel();
    
    await loadDevices();
    await updateStatus();
    // 기본 선택: 전체 선택
    selectAllDevices();
    setupEventListeners();
    startAutoRefresh();
}

// 장치 목록 로드
async function loadDevices() {
    const allDevices = await api.getDevices();
    const allDeviceIds = DEVICE_GRID_ORDER.flat();
    
    // 장치를 고정 순서로 정렬
    devices = allDeviceIds.map(id => {
        const device = allDevices.find(d => d.id === id);
        // 새로 발견된 장치의 health 히스토리 초기화
        if (device && !healthHistory[id]) {
            healthHistory[id] = {
                recent: [],
                stable: false,
                lastChangeTime: Date.now()
            };
        }
        return device || { id, ip: '', port: 80 }; // 없으면 빈 장치로 표시
    });
    
    renderDevices();
}

// Health 상태 안정화 함수
function updateHealthStability(deviceId, isHealthy) {
    if (!healthHistory[deviceId]) {
        healthHistory[deviceId] = {
            recent: [],
            stable: isHealthy,
            lastChangeTime: Date.now()
        };
    }
    
    const history = healthHistory[deviceId];
    const now = Date.now();
    
    // 최근 상태 추가 (타임스탬프 포함)
    history.recent.push({
        healthy: isHealthy,
        timestamp: now
    });
    
    // 최대 개수 유지
    if (history.recent.length > HEALTH_HISTORY_SIZE) {
        history.recent.shift();
    }
    
    // 히스토리가 부족하면 현재 상태 사용 (초기 상태)
    if (history.recent.length < 3) {
        history.stable = isHealthy;
        return history.stable;
    }
    
    // 현재 안정화된 상태
    const currentStable = history.stable;
    
    // 상태 변경이 필요한지 확인
    if (currentStable === isHealthy) {
        // 현재 상태와 같으면 그대로 유지
        return currentStable;
    }
    
    // 상태가 다를 때만 변경 여부 판단
    if (!currentStable && isHealthy) {
        // Unhealthy → Healthy: 더 엄격한 조건 필요
        
        // 방법 1: 연속 성공 횟수 확인
        const recentHealthy = history.recent.slice(-HEALTH_TO_HEALTHY_SUCCESSES);
        if (recentHealthy.length >= HEALTH_TO_HEALTHY_SUCCESSES) {
            const allHealthy = recentHealthy.every(entry => entry.healthy);
            if (allHealthy) {
                history.stable = true;
                history.lastChangeTime = now;
                return true;
            }
        }
        
        // 방법 2: 최근 히스토리 비율 확인
        const recentEntries = history.recent.slice(-HEALTH_HISTORY_SIZE);
        const successCount = recentEntries.filter(entry => entry.healthy).length;
        const successRatio = successCount / recentEntries.length;
        
        if (successRatio >= HEALTH_MIN_SUCCESS_RATIO && recentEntries.length >= 5) {
            history.stable = true;
            history.lastChangeTime = now;
            return true;
        }
        
        // 조건을 만족하지 않으면 기존 상태 유지
        return currentStable;
        
    } else if (currentStable && !isHealthy) {
        // Healthy → Unhealthy: 더 완화된 조건 (일시적 실패 허용)
        
        // 방법 1: 연속 실패 횟수 확인
        const recentUnhealthy = history.recent.slice(-HEALTH_TO_UNHEALTHY_FAILURES);
        if (recentUnhealthy.length >= HEALTH_TO_UNHEALTHY_FAILURES) {
            const allUnhealthy = recentUnhealthy.every(entry => !entry.healthy);
            if (allUnhealthy) {
                history.stable = false;
                history.lastChangeTime = now;
                return false;
            }
        }
        
        // 방법 2: 최근 히스토리 비율 확인
        const recentEntries = history.recent.slice(-HEALTH_HISTORY_SIZE);
        const failureCount = recentEntries.filter(entry => !entry.healthy).length;
        const failureRatio = failureCount / recentEntries.length;
        
        if (failureRatio >= HEALTH_MIN_FAILURE_RATIO && recentEntries.length >= 5) {
            history.stable = false;
            history.lastChangeTime = now;
            return false;
        }
        
        // 조건을 만족하지 않으면 기존 상태 유지
        return currentStable;
    }
    
    return currentStable;
}

// 상태 업데이트
async function updateStatus() {
    try {
        const statuses = await api.getAllStatus();
        
        // 상태를 객체로 변환하고 health 안정화 적용
        deviceStatuses = {};
        
        // statuses가 배열인지 확인
        if (!statuses || !Array.isArray(statuses)) {
            // null이거나 배열이 아니면 빈 배열로 처리
            console.warn('getAllStatus returned non-array:', statuses);
            renderDevices();
            return;
        }
        
        statuses.forEach(status => {
            const rawHealthy = status?.health?.ok || false;
            const stableHealthy = updateHealthStability(status.id, rawHealthy);
            
            // 안정화된 health 상태로 덮어쓰기
            deviceStatuses[status.id] = {
                ...status,
                health: {
                    ...status.health,
                    ok: stableHealthy,
                    raw: rawHealthy // 원본 상태도 보관 (디버깅용)
                }
            };
        });
        
        renderDevices();
    } catch (error) {
        console.error('Error in updateStatus:', error);
        renderDevices();
    }
}

// 장치 카드 렌더링
function renderDevices() {
    const devicesGrid = document.getElementById('devicesGrid');
    devicesGrid.innerHTML = '';
    
    // 2열 그리드로 렌더링
    DEVICE_GRID_ORDER.forEach(row => {
        row.forEach(deviceId => {
            const card = createDeviceCard(deviceId);
            if (card) devicesGrid.appendChild(card);
        });
    });
}

// 장치 카드 생성 함수
function createDeviceCard(deviceId) {
        const device = devices.find(d => d.id === deviceId);
        const status = deviceStatuses[deviceId];
        const isHealthy = status?.health?.ok || false;
        const state = status?.state || null;
        const isOn = state?.power === true || state?.power === 'true';
        const roomTemp = state?.room_temp !== null && state?.room_temp !== undefined 
            ? parseFloat(state.room_temp).toFixed(1) 
            : '--';
        const setTemp = state?.temp !== null && state?.temp !== undefined
            ? parseInt(state.temp, 10)
            : null;
        const mode = state?.mode || null;
        const modeText = mode === 'hot' ? '난방' : mode === 'cool' ? '냉방' : '';
        
        const card = document.createElement('div');
        const isSelected = selectedDeviceIds.includes(deviceId);
        const exists = device && device.ip; // 실제 장치가 존재하는지 확인
        const isPending = pendingDevices.has(deviceId); // 진행중인지 확인
        const hasTemp = roomTemp !== '--'; // 온도 정보가 있는지 확인
        const hasIssue = !hasTemp || !isHealthy; // 온도 정보가 없거나 health가 안 좋으면 문제
        
        card.className = `device-card ${isSelected ? 'selected' : ''} ${isPending ? 'pending' : ''}`;
        card.dataset.deviceId = deviceId;
        
        // 진행중이 아닐 때만 클릭 가능
        if (!isPending) {
            card.addEventListener('click', () => selectDevice(deviceId));
        }
        
        const location = DEVICE_LOCATIONS[deviceId] || '';
        const floor = DEVICE_FLOOR[deviceId] || '';
        const cardMode = isOn && mode ? mode : null; // 카드 배경색용 모드
        
        card.innerHTML = `
            <div class="device-floor-badge">${floor}</div>
            <div class="device-header">
                <div class="device-id">
                    <span class="device-location-strong">${location}</span>
                    <span class="device-id-inline">${deviceId}</span>
                </div>
                <div class="device-status">
                    ${isPending ? '<div class="status-indicator pending-indicator"></div>' : `<div class="status-indicator ${!hasIssue ? 'active' : 'inactive'}"></div>`}
                </div>
            </div>
            <div class="device-info device-info-row">
                <div class="power-status">
                    ${isPending
                        ? '<span class="pending-text">진행중...</span>'
                        : `<span class="power-icon ${isOn ? 'on' : 'off'}">${isOn ? '●' : '○'}</span><span>${isOn ? 'ON' : 'OFF'}</span>${isOn && modeText ? `<span class="mode-badge mode-${mode}">${modeText}</span>` : ''}`
                    }
                </div>
                <div class="temp-right">
                    <span class="temp-line">
                        <span class="temp-label">설정</span>
                        <span class="temp-value">${setTemp !== null ? `${setTemp}&deg;` : '--'}</span>
                    </span>
                    <span class="temp-line">
                        <span class="temp-label">현재</span>
                        <span class="temp-value">${roomTemp !== '--' ? `${roomTemp}&deg;` : '--'}</span>
                    </span>
                    ${isPending ? '<span class="temp-suffix">전송중</span>' : ''}
                </div>
            </div>
        `;
        
        // 모드에 따른 카드 배경색 클래스 추가
        if (cardMode === 'hot') {
            card.classList.add('mode-hot-bg');
        } else if (cardMode === 'cool') {
            card.classList.add('mode-cool-bg');
        }
        
        return card;
    }

// 장치 선택 (단일)
function selectDevice(deviceId) {
    selectedDeviceIds = [deviceId];
    const status = deviceStatuses[deviceId];
    const state = status?.state;
    
    if (state) {
        // 현재 상태로 제어 패널 업데이트
        currentCommand.power = state.power ? 'on' : 'off';
        currentCommand.mode = state.mode === 'hot' ? 'hot' : 'cool';
        currentCommand.temp = state.temp || 24;
        currentCommand.fan = state.fan || 'auto';
        currentCommand.swing = state.swing ? 'on' : 'off';
    }
    
    updateControlPanel();
    renderDevices();
}

// 모든 장치 선택
function selectAllDevices() {
    const allDeviceIds = DEVICE_GRID_ORDER.flat();
    
    // 장치 목록이 비어있으면 로드 먼저 시도
    if (devices.length === 0) {
        console.warn('장치 목록이 비어있습니다. 장치를 먼저 로드하세요.');
        // 장치 목록을 다시 로드 시도
        loadDevices().then(() => {
            // 로드 후 다시 선택 시도
            selectAllDevices();
        });
        return;
    }
    
    // 모든 장치를 선택 (IP가 없어도 선택 가능 - 제어는 안 될 수 있지만 선택은 가능)
    selectedDeviceIds = allDeviceIds.filter(deviceId => {
        const device = devices.find(d => d.id === deviceId);
        return device !== undefined; // 장치가 존재하면 선택
    });
    
    console.log('전체 선택:', selectedDeviceIds.length, '개 선택됨. 전체 장치:', devices.length, '개'); // 디버깅용
    
    // 첫 번째 장치의 상태로 제어 패널 초기화 (상태가 있으면)
    if (selectedDeviceIds.length > 0) {
        // 전체선택 시 f3-ac-01을 기준으로 제어 설정 생성 (없으면 첫 번째 선택 장치로 대체)
        let baseId = 'f3-ac-01';
        let baseStatus = null;
        if (selectedDeviceIds.includes(baseId) && deviceStatuses[baseId]) {
            baseStatus = deviceStatuses[baseId];
        } else {
            baseId = selectedDeviceIds[0];
            baseStatus = deviceStatuses[baseId];
        }
        const state = baseStatus?.state;
        
        if (state) {
            currentCommand.power = state.power ? 'on' : 'off';
            currentCommand.mode = state.mode === 'hot' ? 'hot' : 'cool';
            currentCommand.temp = state.temp || 24;
            currentCommand.fan = state.fan || 'auto';
            currentCommand.swing = state.swing ? 'on' : 'off';
        }
        // 상태가 없어도 기본값은 이미 currentCommand에 있음
    }
    
    // 제어 패널 업데이트 (선택된 장치 정보 표시) - 반드시 호출
    updateControlPanel();
    renderDevices();
}

// 제어 패널 업데이트
function updateControlPanel() {
    // 전원
    updateToggleGroup('power', currentCommand.power);
    
    // 모드
    updateToggleGroup('mode', currentCommand.mode);
    // 테마 적용 (냉방일 때 시원한 색상)
    try {
        if (currentCommand.mode === 'cool') {
            document.body.classList.add('theme-cool');
        } else {
            document.body.classList.remove('theme-cool');
        }
    } catch (e) {}
    
    // 온도
    document.getElementById('tempValue').textContent = currentCommand.temp;
    
    // 풍량
    updateButtonGroup('fan', currentCommand.fan);
    
    // 풍향
    updateToggleGroup('swing', currentCommand.swing);
    
    // 선택된 장치 표시
    if (selectedDeviceIds.length === 0) {
        selectedDeviceText.textContent = '제어할 장치를 선택하세요';
    } else if (selectedDeviceIds.length === 1) {
        selectedDeviceText.textContent = `선택: ${selectedDeviceIds[0]}`;
    } else {
        selectedDeviceText.textContent = '전체선택';
    }
    
    // 설정 저장
    saveCommand(currentCommand);
}

// 토글 그룹 업데이트
function updateToggleGroup(type, value) {
    const controlItems = document.querySelectorAll('.control-item');
    controlItems.forEach(item => {
        const label = item.querySelector('label').textContent;
        let targetLabel = '';
        if (type === 'power') targetLabel = '전원';
        else if (type === 'mode') targetLabel = '운전 모드';
        else if (type === 'swing') targetLabel = '풍향 자동';
        
        if (label === targetLabel) {
            const buttons = item.querySelectorAll('.toggle-group button[data-value]');
            buttons.forEach(btn => {
                btn.classList.toggle('active', btn.dataset.value === value);
            });
        }
    });
}

// 버튼 그룹 업데이트
function updateButtonGroup(type, value) {
    const controlItems = document.querySelectorAll('.control-item');
    controlItems.forEach(item => {
        const label = item.querySelector('label').textContent;
        if (label === '풍량') {
            const buttons = item.querySelectorAll('.button-group .btn-option');
            buttons.forEach(btn => {
                btn.classList.toggle('active', btn.dataset.value === value);
            });
        }
    });
}

// 제어 패널 활성화 (항상 보이므로 별도 함수 불필요)

// 이벤트 리스너 설정
function setupEventListeners() {
    // ALL 버튼 - 모든 장치 선택
    const allSelectBtn = document.getElementById('allSelectBtn');
    if (allSelectBtn) {
        allSelectBtn.addEventListener('click', () => {
            selectAllDevices();
        });
    }
    
    // 전체 켜기/끄기 (빠른 제어용 - 제어 패널 열지 않음)
    allOnBtn.addEventListener('click', async () => {
        setActionButtonsDisabled(true);
        // 온도 정보가 있는 장치를 진행중으로 표시
        const allDeviceIds = DEVICE_GRID_ORDER.flat();
        allDeviceIds.forEach(deviceId => {
            const device = devices.find(d => d.id === deviceId);
            const status = deviceStatuses[deviceId];
            const state = status?.state || null;
            const hasTemp = state?.room_temp !== null && state?.room_temp !== undefined;
            if (device && device.ip && hasTemp) {
                pendingDevices.add(deviceId);
            }
        });
        renderDevices();
        
        try {
            const result = await api.allOn();
            if (result) {
                pendingDevices.clear();
                await updateStatus();
            } else {
                pendingDevices.clear();
                renderDevices();
            }
        } finally {
            setActionButtonsDisabled(false);
        }
    });
    
    allOffBtn.addEventListener('click', async () => {
        setActionButtonsDisabled(true);
        // 온도 정보가 있는 장치를 진행중으로 표시
        const allDeviceIds = DEVICE_GRID_ORDER.flat();
        allDeviceIds.forEach(deviceId => {
            const device = devices.find(d => d.id === deviceId);
            const status = deviceStatuses[deviceId];
            const state = status?.state || null;
            const hasTemp = state?.room_temp !== null && state?.room_temp !== undefined;
            if (device && device.ip && hasTemp) {
                pendingDevices.add(deviceId);
            }
        });
        renderDevices();
        
        try {
            const result = await api.allOff();
            if (result) {
                pendingDevices.clear();
                await updateStatus();
            } else {
                pendingDevices.clear();
                renderDevices();
            }
        } finally {
            setActionButtonsDisabled(false);
        }
    });
    
    // 토글 버튼 (이벤트 위임 사용)
    document.addEventListener('click', function(e) {
        if (e.target.classList.contains('toggle-btn')) {
            const btn = e.target;
            const group = btn.closest('.toggle-group');
            if (group) {
                group.querySelectorAll('.toggle-btn').forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                
                const label = btn.closest('.control-item').querySelector('label').textContent;
                const value = btn.dataset.value;
                
                if (label === '전원') {
                    currentCommand.power = value;
                    saveCommand(currentCommand);
                } else if (label === '운전 모드') {
                    currentCommand.mode = value;
                    saveCommand(currentCommand);
                    // 모드 변경 즉시 테마 반영
                    try {
                        if (currentCommand.mode === 'cool') {
                            document.body.classList.add('theme-cool');
                        } else {
                            document.body.classList.remove('theme-cool');
                        }
                    } catch (e) {}
                } else if (label === '풍향 자동') {
                    currentCommand.swing = value;
                    saveCommand(currentCommand);
                }
            }
        }
    });
    
    // 온도 조절
    document.getElementById('tempDown').addEventListener('click', () => {
        if (currentCommand.temp > 16) {
            currentCommand.temp--;
            document.getElementById('tempValue').textContent = currentCommand.temp;
            saveCommand(currentCommand);
        }
    });
    
    document.getElementById('tempUp').addEventListener('click', () => {
        if (currentCommand.temp < 30) {
            currentCommand.temp++;
            document.getElementById('tempValue').textContent = currentCommand.temp;
            saveCommand(currentCommand);
        }
    });
    
    // 풍량 버튼 (이벤트 위임 사용)
    document.addEventListener('click', function(e) {
        if (e.target.classList.contains('btn-option')) {
            const btn = e.target;
            const group = btn.closest('.button-group');
            if (group) {
                group.querySelectorAll('.btn-option').forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                currentCommand.fan = btn.dataset.value;
                saveCommand(currentCommand);
            }
        }
    });
    
    // 적용 버튼 - 선택된 장치(들)에 적용
    applyBtn.addEventListener('click', async () => {
        if (selectedDeviceIds.length === 0) {
            return;
        }
        setActionButtonsDisabled(true);
        
        // 선택된 모든 장치를 진행중으로 표시
        selectedDeviceIds.forEach(deviceId => {
            pendingDevices.add(deviceId);
        });
        renderDevices();
        
        const command = { ...currentCommand };
        
        try {
            if (selectedDeviceIds.length > 1) {
                // 2개 이상 선택 시 서버 배치 엔드포인트 사용(서버에서 스레드 병렬 처리)
                await api.setDevicesBatch(selectedDeviceIds, command);
                pendingDevices.clear();
            } else {
                // 단일 선택은 기존 단일 엔드포인트 사용
                const onlyId = selectedDeviceIds[0];
                await api.setDevice(onlyId, command);
                pendingDevices.delete(onlyId);
            }
            await updateStatus();
        } finally {
            // 실패/성공 모두 버튼 복구 및 렌더링 반영
            if (selectedDeviceIds.length > 1) {
                pendingDevices.clear();
            }
            renderDevices();
            setActionButtonsDisabled(false);
        }
    });
    
    // 제어 패널 페이저 탭
    const pager = document.getElementById('controlPager');
    const tab1 = document.getElementById('pagerTo1');
    const tab2 = document.getElementById('pagerTo2');
    function setActiveTab(idx) {
        if (!tab1 || !tab2) return;
        tab1.classList.toggle('active', idx === 0);
        tab2.classList.toggle('active', idx === 1);
    }
    function goToPage(idx) {
        if (!pager) return;
        const x = idx * pager.clientWidth;
        pager.scrollTo({ left: x, behavior: 'smooth' });
        setActiveTab(idx);
    }
    if (tab1) tab1.addEventListener('click', () => goToPage(0));
    if (tab2) tab2.addEventListener('click', () => goToPage(1));
    if (pager) {
        pager.addEventListener('scroll', () => {
            const idx = Math.round(pager.scrollLeft / Math.max(1, pager.clientWidth));
            setActiveTab(Math.min(1, Math.max(0, idx)));
        });
    }
}

// 자동 새로고침
function startAutoRefresh() {
    setInterval(async () => {
        await updateStatus();
    }, 5000); // 5초마다 업데이트
    
    // 초기 health 히스토리 초기화
    const allDeviceIds = DEVICE_GRID_ORDER.flat();
    allDeviceIds.forEach(deviceId => {
        if (!healthHistory[deviceId]) {
            healthHistory[deviceId] = {
                recent: [],
                stable: false,
                lastChangeTime: Date.now()
            };
        }
    });
}

// 페이지 로드 시 초기화
document.addEventListener('DOMContentLoaded', init);

