// API 기본 URL (외부 제어용 백엔드)
// 우선순위: URL ?api= → localStorage apiBaseUrl → 현재 페이지 origin → 기본값(내부망 고정 IP)
const DEFAULT_API_BASE_URL = 'http://192.168.0.5:8000';
const API_BASE_URL = (() => {
  try {
    const params = new URLSearchParams(window.location.search);
    const fromQuery = params.get('api');
    const fromStorage = localStorage.getItem('apiBaseUrl');
    const fromSameOrigin = (() => {
      try {
        const origin = window.location?.origin ?? '';
        if (!origin || origin === 'null') return '';
        // file:// 등의 스킴은 건너뜀
        if (!/^https?:/i.test(origin)) return '';
        return origin;
      } catch {
        return '';
      }
    })();
    const base = (fromQuery || fromStorage || fromSameOrigin || DEFAULT_API_BASE_URL).trim();
    // 마지막 슬래시 제거
    return base.replace(/\/+$/, '');
  } catch (_) {
    return DEFAULT_API_BASE_URL;
  }
})();

// 선택적으로 런타임에 API 주소 변경
window.setApiBaseUrl = function (url) {
  try {
    if (!url) return;
    localStorage.setItem('apiBaseUrl', url);
    window.location.reload();
  } catch (_) {}
};
const DEFAULT_API_TIMEOUT_MS = 10000;

function fetchWithTimeout(url, options = {}, timeoutMs = DEFAULT_API_TIMEOUT_MS) {
    const controller = new AbortController();
    const id = setTimeout(() => controller.abort(), timeoutMs);
    const opts = { ...options, signal: controller.signal };
    return fetch(url, opts)
        .finally(() => clearTimeout(id));
}

// API 통신 함수
const api = {
    // 모든 장치 목록 조회
    async getDevices() {
        try {
            const response = await fetchWithTimeout(`${API_BASE_URL}/devices`);
            if (!response.ok) throw new Error('Failed to fetch devices');
            return await response.json();
        } catch (error) {
            console.error('Error fetching devices:', error);
            return [];
        }
    },
    // 예약 스케줄 전체 조회
    async getSchedules() {
        try {
            const response = await fetchWithTimeout(`${API_BASE_URL}/schedules`);
            if (!response.ok) throw new Error('Failed to fetch schedules');
            return await response.json();
        } catch (error) {
            console.error('Error fetching schedules:', error);
            return [];
        }
    },
    // 예약 스케줄 업데이트
    async updateSchedule(scheduleId, payload) {
        try {
            const response = await fetchWithTimeout(`${API_BASE_URL}/schedules/${scheduleId}`, {
                method: 'PUT',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(payload || {}),
            });
            if (!response.ok) throw new Error('Failed to update schedule');
            return await response.json();
        } catch (error) {
            console.error('Error updating schedule:', error);
            return { ok: false, error: error.message };
        }
    },

    // 선택된 여러 장치 제어(백엔드 병렬 엔드포인트)
    async setDevicesBatch(deviceIds, command) {
        if (!Array.isArray(deviceIds) || deviceIds.length === 0) {
            throw new Error('No device ids provided');
        }

        const payload = {
            device_ids: deviceIds,
            command: command || {},
        };

        const endpoints = ['/devices/control', '/devices/batch/ac/set'];
        let lastError = null;

        for (const path of endpoints) {
            try {
                const response = await fetchWithTimeout(`${API_BASE_URL}${path}`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify(payload),
                });

                if (response.status === 404 || response.status === 405) {
                    lastError = new Error(`Endpoint ${path} is not available`);
                    continue;
                }

                if (!response.ok) {
                    const text = await response.text().catch(() => '');
                    throw new Error(`Batch request failed (${response.status} ${response.statusText}) ${text}`);
                }

                const data = await response.json();
                return { ...data, _endpoint: path };
            } catch (error) {
                lastError = error;
                console.warn(`Batch API call failed at ${path}:`, error);
            }
        }

        throw lastError || new Error('No batch control endpoint responded');
    },

    // 모든 장치 상태 조회
    async getAllStatus() {
        try {
            const response = await fetchWithTimeout(`${API_BASE_URL}/devices/status`);
            if (!response.ok) {
                console.error('Failed to fetch status:', response.status, response.statusText);
                return [];
            }
            const data = await response.json();
            // null이나 undefined인 경우 빈 배열 반환
            return Array.isArray(data) ? data : [];
        } catch (error) {
            console.error('Error fetching status:', error);
            return [];
        }
    },

    // 특정 장치 상태 조회
    async getDeviceState(deviceId) {
        try {
            const response = await fetchWithTimeout(`${API_BASE_URL}/devices/${deviceId}/ac/state`);
            if (!response.ok) throw new Error('Failed to fetch device state');
            return await response.json();
        } catch (error) {
            console.error('Error fetching device state:', error);
            return null;
        }
    },

    // 특정 장치 제어
    async setDevice(deviceId, command) {
        try {
            const response = await fetchWithTimeout(`${API_BASE_URL}/devices/${deviceId}/ac/set`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(command),
            });
            if (!response.ok) throw new Error('Failed to set device');
            return await response.json();
        } catch (error) {
            console.error('Error setting device:', error);
            return { ok: false, error: error.message };
        }
    },

    // 모든 장치 켜기
    async allOn(command = null) {
        try {
            const response = await fetchWithTimeout(`${API_BASE_URL}/all/on`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(command || {}),
            });
            if (!response.ok) throw new Error('Failed to turn on all devices');
            return await response.json();
        } catch (error) {
            console.error('Error turning on all devices:', error);
            return { ok: false, error: error.message };
        }
    },

    // 모든 장치 끄기
    async allOff() {
        try {
            const response = await fetchWithTimeout(`${API_BASE_URL}/all/off`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
            });
            if (!response.ok) throw new Error('Failed to turn off all devices');
            return await response.json();
        } catch (error) {
            console.error('Error turning off all devices:', error);
            return { ok: false, error: error.message };
        }
    },
};

