// API 기본 URL (현재 호스트 사용)
const API_BASE_URL = window.location.origin;

// API 통신 함수
const api = {
    // 모든 장치 목록 조회
    async getDevices() {
        try {
            const response = await fetch(`${API_BASE_URL}/devices`);
            if (!response.ok) throw new Error('Failed to fetch devices');
            return await response.json();
        } catch (error) {
            console.error('Error fetching devices:', error);
            return [];
        }
    },

    // 모든 장치 상태 조회
    async getAllStatus() {
        try {
            const response = await fetch(`${API_BASE_URL}/devices/status`);
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
            const response = await fetch(`${API_BASE_URL}/devices/${deviceId}/ac/state`);
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
            const response = await fetch(`${API_BASE_URL}/devices/${deviceId}/ac/set`, {
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
            const response = await fetch(`${API_BASE_URL}/all/on`, {
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
            const response = await fetch(`${API_BASE_URL}/all/off`, {
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

