// 고정된 장치 순서
const DEVICE_ORDER = [
    'f3-ac-01',
    'f3-ac-02',
    'f3-ac-03',
    'f3-ac-04',
    'f4-ac-01',
    'f4-ac-02'
];

// 전역 상태
let devices = [];
let deviceStatuses = {};
let selectedDeviceIds = []; // 여러 장치 선택 가능

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

// 초기화
async function init() {
    // 저장된 설정으로 제어 패널 초기화
    updateControlPanel();
    
    await loadDevices();
    await updateStatus();
    setupEventListeners();
    startAutoRefresh();
}

// 장치 목록 로드
async function loadDevices() {
    const allDevices = await api.getDevices();
    
    // 장치를 고정 순서로 정렬
    devices = DEVICE_ORDER.map(id => {
        const device = allDevices.find(d => d.id === id);
        return device || { id, ip: '', port: 80 }; // 없으면 빈 장치로 표시
    });
    
    renderDevices();
}

// 상태 업데이트
async function updateStatus() {
    const statuses = await api.getAllStatus();
    
    // 상태를 객체로 변환
    deviceStatuses = {};
    statuses.forEach(status => {
        deviceStatuses[status.id] = status;
    });
    
    renderDevices();
}

// 장치 카드 렌더링
function renderDevices() {
    devicesGrid.innerHTML = '';
    
    // 고정된 순서로 6개 장치 표시
    DEVICE_ORDER.forEach(deviceId => {
        const device = devices.find(d => d.id === deviceId);
        const status = deviceStatuses[deviceId];
        const isHealthy = status?.health?.ok || false;
        const state = status?.state || null;
        const isOn = state?.power === true || state?.power === 'true';
        const roomTemp = state?.room_temp !== null && state?.room_temp !== undefined 
            ? parseFloat(state.room_temp).toFixed(1) 
            : '--';
        
        const card = document.createElement('div');
        const isSelected = selectedDeviceIds.includes(deviceId);
        const exists = device && device.ip; // 실제 장치가 존재하는지 확인
        
        card.className = `device-card ${!exists || !isHealthy ? 'disabled' : ''} ${isSelected ? 'selected' : ''}`;
        card.dataset.deviceId = deviceId;
        
        if (exists && isHealthy) {
            card.addEventListener('click', () => selectDevice(deviceId));
        }
        
        card.innerHTML = `
            <div class="device-header">
                <div class="device-id">${deviceId}</div>
                <div class="device-status">
                    <div class="status-indicator ${exists && isHealthy ? 'active' : 'inactive'}"></div>
                </div>
            </div>
            <div class="device-info">
                <div class="power-status">
                    <span class="power-icon ${isOn ? 'on' : 'off'}">${isOn ? '●' : '○'}</span>
                    <span>${isOn ? 'ON' : 'OFF'}</span>
                </div>
                <div class="temp-display">${roomTemp}°</div>
                <div class="temp-label">실내온도</div>
            </div>
        `;
        
        devicesGrid.appendChild(card);
    });
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
    selectedDeviceIds = DEVICE_ORDER
        .filter(deviceId => {
            const device = devices.find(d => d.id === deviceId);
            const status = deviceStatuses[deviceId];
            return device && device.ip && status?.health?.ok === true;
        });
    
    // 첫 번째 장치의 상태로 제어 패널 초기화
    if (selectedDeviceIds.length > 0) {
        const firstStatus = deviceStatuses[selectedDeviceIds[0]];
        const state = firstStatus?.state;
        
        if (state) {
            currentCommand.power = state.power ? 'on' : 'off';
            currentCommand.mode = state.mode === 'hot' ? 'hot' : 'cool';
            currentCommand.temp = state.temp || 24;
            currentCommand.fan = state.fan || 'auto';
            currentCommand.swing = state.swing ? 'on' : 'off';
        }
    }
    
    updateControlPanel();
    renderDevices();
}

// 제어 패널 업데이트
function updateControlPanel() {
    // 전원
    updateToggleGroup('power', currentCommand.power);
    
    // 모드
    updateToggleGroup('mode', currentCommand.mode);
    
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
        selectedDeviceText.textContent = `선택: 전체 (${selectedDeviceIds.length}개)`;
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
        const result = await api.allOn();
        if (result) {
            await updateStatus();
            alert('전체 장치가 켜졌습니다.');
        }
    });
    
    allOffBtn.addEventListener('click', async () => {
        const result = await api.allOff();
        if (result) {
            await updateStatus();
            alert('전체 장치가 꺼졌습니다.');
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
            alert('제어할 장치를 선택해주세요.');
            return;
        }
        
        const command = { ...currentCommand };
        let successCount = 0;
        let failCount = 0;
        
        // 선택된 모든 장치에 명령 전송
        for (const deviceId of selectedDeviceIds) {
            const result = await api.setDevice(deviceId, command);
            if (result && result.result && result.result.ok) {
                successCount++;
            } else {
                failCount++;
            }
        }
        
        await updateStatus();
        
        if (failCount === 0) {
            alert(`${successCount}개 장치에 설정이 적용되었습니다.`);
        } else {
            alert(`적용 완료: ${successCount}개, 실패: ${failCount}개`);
        }
    });
    
}

// 자동 새로고침
function startAutoRefresh() {
    setInterval(async () => {
        await updateStatus();
    }, 5000); // 5초마다 업데이트
}

// 페이지 로드 시 초기화
document.addEventListener('DOMContentLoaded', init);

