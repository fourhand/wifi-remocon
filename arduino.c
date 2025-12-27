// ---------------------------
// Wi-Fi 설정
// ---------------------------
// const char* SSID = "kyeyoulddd";
// const char* PASS = "000000d750&&";
//const char* SSID = "fourhand_2g";
//const char* PASS = "lyb_99028386";
const char* SSID = "ydch-4 studio 2.4";
const char* PASS = "a1234567890";
// ---------------------------
// 라이브러리
// ---------------------------
#include <ESP.h>
#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>
#include <ESP8266mDNS.h>
#include <ESP8266HTTPClient.h>
#include <IRremoteESP8266.h>
#include <IRsend.h>
#include <ir_Samsung.h>
#include <DHT.h>
#include <WiFiUdp.h>
#include <EEPROM.h>

// ---------------------------
// 기본 설정
// ---------------------------
static const char* HOST = "f4-ac-01";
static const uint16_t HTTP_PORT = 80;
static const uint16_t UDP_PORT  = 4210;
static const unsigned long MDNS_ANNOUNCE_MS = 120000;

#define ENABLE_HEARTBEAT 0

unsigned long g_lastMdnsAnnounce = 0;

// IR / LED 핀
#define IR_PIN 14  // D5
#define LED_G 13   // D7
#define LED_R 12   // D6

// DHT22
#define DHTPIN 5   // D1
#define DHTTYPE DHT22
DHT dht(DHTPIN, DHTTYPE);

float g_lastTempC = NAN;
unsigned long g_lastDhtMs = 0;

// IR 송신 표시 타이머(2초)
unsigned long g_irLedUntilMs = 0;

// 서버 명령 수신 표시 타이머(1초) ★
unsigned long g_preSignalUntilMs = 0;

// 최근 브로드캐스트 송신자(백엔드)로 상태 푸시 스케줄링
IPAddress g_backendIp;
uint16_t  g_backendPort = 0;
bool      g_statusPushPending = false;
unsigned long g_statusPushDueMs = 0;
static const uint16_t BACKEND_HTTP_PORT_DEFAULT = 8000;
uint16_t g_backendHttpPort = BACKEND_HTTP_PORT_DEFAULT;

// ---------------------------
// AC 상태 저장
// ---------------------------
bool    st_power = true;
uint8_t st_mode  = kSamsungAcCool;
uint8_t st_temp  = 24;
uint8_t st_fan   = kSamsungAcFanAuto;
bool    st_swing = false;

// ---------------------------
ESP8266WebServer server(HTTP_PORT);
IRSamsungAc ac(IR_PIN);
WiFiUDP udp;

// ---------------------------
// EEPROM 상태 저장/복원
// ---------------------------
#define EEPROM_SIZE 64
#define EEPROM_ADDR 0

static const uint32_t STATE_MAGIC = 0x41435354; // 'ACST'
static const uint8_t  STATE_VER   = 1;

struct PersistState {
  uint32_t magic;
  uint8_t  version;
  uint8_t  power;   // 0/1
  uint8_t  mode;    // kSamsungAcCool / kSamsungAcHeat
  uint8_t  temp;    // 16..30
  uint8_t  fan;     // auto/low/med/high
  uint8_t  swing;   // 0/1
  uint8_t  checksum;
};

inline uint8_t calcChecksum(const PersistState& s) {
  uint16_t sum = 0;
  sum += (uint8_t)(s.magic & 0xFF);
  sum += (uint8_t)((s.magic >> 8) & 0xFF);
  sum += (uint8_t)((s.magic >> 16) & 0xFF);
  sum += (uint8_t)((s.magic >> 24) & 0xFF);
  sum += s.version;
  sum += s.power;
  sum += s.mode;
  sum += s.temp;
  sum += s.fan;
  sum += s.swing;
  return (uint8_t)(sum & 0xFF);
}

bool isValidRanges(const PersistState& s) {
  bool modeOk = (s.mode == kSamsungAcCool || s.mode == kSamsungAcHeat);
  bool tempOk = (s.temp >= 16 && s.temp <= 30);
  bool fanOk  = (s.fan == kSamsungAcFanAuto ||
                 s.fan == kSamsungAcFanLow  ||
                 s.fan == kSamsungAcFanMed  ||
                 s.fan == kSamsungAcFanHigh);
  return modeOk && tempOk && fanOk;
}

void saveStateToEeprom() {
  PersistState p;
  p.magic   = STATE_MAGIC;
  p.version = STATE_VER;
  p.power   = st_power ? 1 : 0;
  p.mode    = st_mode;
  p.temp    = st_temp;
  p.fan     = st_fan;
  p.swing   = st_swing ? 1 : 0;
  p.checksum = 0;
  p.checksum = calcChecksum(p);

  EEPROM.begin(EEPROM_SIZE);
  EEPROM.put(EEPROM_ADDR, p);
  EEPROM.commit();
}

void loadStateFromEeprom() {
  EEPROM.begin(EEPROM_SIZE);
  PersistState p;
  EEPROM.get(EEPROM_ADDR, p);
  if (p.magic == STATE_MAGIC &&
      p.version == STATE_VER &&
      p.checksum == calcChecksum(p) &&
      isValidRanges(p)) {
    st_power = (p.power != 0);
    st_mode  = p.mode;
    st_temp  = p.temp;
    st_fan   = p.fan;
    st_swing = (p.swing != 0);
  } else {
    // 초기 상태(유효 저장 없음) → 현재 기본값을 저장해 다음 부팅부터 유지
    saveStateToEeprom();
  }
}

// ---------------------------
// CORS 헬퍼
// ---------------------------
inline void addCORS() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type, Accept, Origin");
}

// LED 제어
inline void setLed(bool g_on, bool r_on) {
  digitalWrite(LED_G, g_on ? HIGH : LOW);
  digitalWrite(LED_R, r_on ? HIGH : LOW);
}

// ---------------------------
// LED 우선순위 처리
// ---------------------------
// 1) IR 송신 → 노란색(G+R)
// 2) 서버 명령 수신 → 빨강만
// 3) WiFi 상태(Green/Red)
void updateStatusLeds() {
  unsigned long now = millis();

  // IR 송신중 (2초) => Yellow
  if (now < g_irLedUntilMs) {
    setLed(true, true);
    return;
  }

  // 서버 명령 수신 => Red ON (1초)
  if (now < g_preSignalUntilMs) {
    setLed(false, true);
    return;
  }

  // WiFi 상태
  bool ok = (WiFi.status() == WL_CONNECTED);
  setLed(ok, !ok);
}

// ---------------------------
// IR 송신
// ---------------------------
void applyAndSend() {
  Serial.println("\n=== applyAndSend() ===");

  // IR 송신 표시 (2초)
  g_irLedUntilMs = millis() + 2000;
  updateStatusLeds();

  if (st_power) ac.on(); else ac.off();
  ac.setMode(st_mode);
  ac.setTemp(st_temp);
  ac.setFan(st_fan);
  ac.setSwing(st_swing);

  // 백그라운드 작업에 CPU 양보
  yield();
  ac.send();
  yield();

  Serial.println(">>> IR signal sent.\n");
}

// ---------------------------
// 온도 갱신
// ---------------------------
void updateDhtIfNeeded() {
  unsigned long now = millis();
  if (now - g_lastDhtMs < 2500) return;
  g_lastDhtMs = now;

  float t = dht.readTemperature();
  if (!isnan(t)) g_lastTempC = t;
}

// ---------------------------
// JSON 응답
// ---------------------------
String stateJson() {
  updateDhtIfNeeded();
  String j = "{";
  j += "\"power\":" + String(st_power ? "true" : "false") + ",";
  j += "\"mode\":\"" + String(st_mode == kSamsungAcHeat ? "hot" : "cool") + "\",";
  j += "\"temp\":" + String(st_temp) + ",";
  j += "\"fan\":\"";
  j += (st_fan == kSamsungAcFanLow ? "low" :
        st_fan == kSamsungAcFanMed ? "medium" :
        st_fan == kSamsungAcFanHigh ? "high" : "auto");
  j += "\",";
  j += "\"swing\":" + String(st_swing ? "true" : "false") + ",";
  j += "\"room_temp\":" + (isnan(g_lastTempC) ? "null" : String(g_lastTempC, 1));
  j += "}";
  return j;
}

String netJson() {
  String j = "{";
  j += "\"host\":\"" + String(HOST) + "\",";
  j += "\"domain\":\"" + String(HOST) + ".local" + "\",";
  j += "\"ssid\":\"" + WiFi.SSID() + "\",";
  j += "\"ip\":\"" + WiFi.localIP().toString() + "\",";
  j += "\"rssi\":" + String(WiFi.RSSI());
  j += "}";
  return j;
}

// ---------------------------
// 상태 푸시 (UDP 유니캐스트, 브로드캐스트 질의에 대한 별도 푸시)
// ---------------------------
void pushStatusToBackend() {
  if (!g_statusPushPending) return;
  unsigned long now = millis();
  if ((long)(now - g_statusPushDueMs) < 0) return;
  g_statusPushPending = false;

  String payload = String("{\"id\":\"") + HOST +
                   "\",\"domain\":\"" + HOST + ".local" +
                   "\",\"ip\":\"" + WiFi.localIP().toString() +
                   "\",\"port\":" + HTTP_PORT +
                   ",\"state\":" + stateJson() +
                   "}";
  // HTTP PUT로 백엔드에 유니캐스트 전송
  WiFiClient client;
  HTTPClient http;
  String url = String("http://") + g_backendIp.toString() + ":" + String(g_backendHttpPort) + "/devices/put_status";
  if (http.begin(client, url)) {
    http.addHeader("Content-Type", "application/json");
    int code = http.POST(payload);
    (void)code;
    http.end();
  }
  yield();
}

// ---------------------------
// HTTP 핸들러
// ---------------------------
void handleOptions() { addCORS(); server.send(204, "text/plain", ""); }

void handleSet() {
  addCORS();

  // 서버 신호 수신 → Red 1초
  g_preSignalUntilMs = millis() + 1000;
  updateStatusLeds();

  if (server.hasArg("power")) {
    String v = server.arg("power");
    st_power = (v == "on" || v == "1" || v == "true");
  }
  if (server.hasArg("mode")) {
    String m = server.arg("mode");
    st_mode = (m == "hot") ? kSamsungAcHeat : kSamsungAcCool;
  }
  if (server.hasArg("temp")) {
    int t = server.arg("temp").toInt();
    if (t >= 16 && t <= 30) st_temp = t;
  }
  if (server.hasArg("fan")) {
    String f = server.arg("fan");
    if      (f == "auto")   st_fan = kSamsungAcFanAuto;
    else if (f == "low")    st_fan = kSamsungAcFanLow;
    else if (f == "medium") st_fan = kSamsungAcFanMed;
    else if (f == "high")   st_fan = kSamsungAcFanHigh;
  }
  if (server.hasArg("swing")) {
    String s = server.arg("swing");
    st_swing = (s == "on" || s == "1" || s == "true");
  }

  // 상태 변경 저장
  saveStateToEeprom();

  applyAndSend();
  server.send(200, "application/json", stateJson());
}

void handleState()   { addCORS(); server.send(200, "application/json", stateJson()); }
void handleHealth()  { addCORS(); server.send(200, "application/json", "{\"ok\":true}"); }
void handleNetInfo() { addCORS(); server.send(200, "application/json", netJson()); }

void handleNotFound() {
  if (server.method() == HTTP_OPTIONS) return handleOptions();
  addCORS();
  server.send(404, "application/json", "{\"error\":\"not found\"}");
}

// ---------------------------
// WiFi + mDNS
// ---------------------------
void connectWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.persistent(false);
  WiFi.hostname(HOST);
  WiFi.setSleepMode(WIFI_NONE_SLEEP);

  WiFi.begin(SSID, PASS);
  Serial.print("Connecting");

  while (WiFi.status() != WL_CONNECTED) {
    delay(300);
    Serial.print(".");
    // WiFi 스택 유지
    yield();
  }
  Serial.println("\nConnected: " + WiFi.localIP().toString());
}

void startMDNS() {
  if (MDNS.begin(HOST)) {
    MDNS.addService("http", "tcp", HTTP_PORT);
    MDNS.announce();
    g_lastMdnsAnnounce = millis();
  }
}

// ---------------------------
// Heartbeat
// ---------------------------
#if ENABLE_HEARTBEAT
static const unsigned long HEARTBEAT_MIN_MS = 30000;  // 30s
static const unsigned long HEARTBEAT_MAX_MS = 120000; // 120s
unsigned long g_nextHeartbeatMs = 0;

inline unsigned long nextHeartbeatDelayMs() {
  return (unsigned long)random(HEARTBEAT_MIN_MS, HEARTBEAT_MAX_MS + 1);
}

void scheduleNextHeartbeat(unsigned long now) {
  g_nextHeartbeatMs = now + nextHeartbeatDelayMs();
}

void sendHeartbeatIfDue() {
  unsigned long now = millis();
  if ((long)(now - g_nextHeartbeatMs) < 0) return;

  String p = String("{\"id\":\"") + HOST +
             "\",\"ip\":\"" + WiFi.localIP().toString() +
             "\",\"port\":" + HTTP_PORT + "}";

  udp.beginPacket(IPAddress(255,255,255,255), UDP_PORT);
  udp.write((const uint8_t*)p.c_str(), p.length());
  udp.endPacket();

  yield();
  scheduleNextHeartbeat(now);
}
#endif

// ---------------------------
// Discover 응답
// ---------------------------
void handleUdpQuery() {
  int n = udp.parsePacket();
  if (n <= 0) return;

  char buf[96];
  if (n > 95) n = 95;
  int len = udp.read(buf, n);
  buf[len] = 0;

  String q = String(buf);
  q.trim();
  String qLower = q; qLower.toLowerCase();
  String hostLower = String(HOST); hostLower.toLowerCase();

  bool match = (qLower == "discover" ||
                qLower == "whois *" ||
                qLower == ("whois " + hostLower));

  if (!match) return;

  // 즉시 큰 payload로 응답하지 않고, 약간의 지터 후 상태를 유니캐스트로 푸시
  g_backendIp = udp.remoteIP();
  g_backendPort = udp.remotePort();
  // discover 페이로드에서 http_port 힌트가 있으면 반영 (JSON 가벼운 파싱)
  int hp = q.indexOf("\"http_port\"");
  if (hp >= 0) {
    int c = q.indexOf(':', hp);
    if (c >= 0) {
      int end = q.indexOf(',', c + 1);
      if (end < 0) end = q.indexOf('}', c + 1);
      if (end < 0) end = q.length();
      String num = q.substring(c + 1, end);
      num.trim();
      int port = num.toInt();
      if (port > 0 && port < 65536) g_backendHttpPort = (uint16_t)port;
    }
  } else {
    g_backendHttpPort = BACKEND_HTTP_PORT_DEFAULT;
  }
  // 50~300ms 랜덤 지연으로 동시 충돌 완화
  unsigned long jitter = (unsigned long)random(50, 301);
  g_statusPushDueMs = millis() + jitter;
  g_statusPushPending = true;
  yield();
}

// ---------------------------
// Setup
// ---------------------------
void setup() {
  Serial.begin(115200);
  ac.begin();

  pinMode(LED_R, OUTPUT);
  pinMode(LED_G, OUTPUT);

  setLed(false, true);  // 부팅 시 RED

  // 랜덤 지터용 시드 초기화
  randomSeed(ESP.getChipId() ^ micros());

  dht.begin();
  // 부팅 시 저장된 상태 복원 (없으면 현재 기본값을 초기 저장)
  loadStateFromEeprom();
  connectWiFi();
  updateStatusLeds();

  udp.begin(UDP_PORT);
  startMDNS();

  server.on("/health",   HTTP_GET,     handleHealth);
  server.on("/ac/set",   HTTP_GET,     handleSet);
  server.on("/ac/set",   HTTP_OPTIONS, handleOptions);
  server.on("/ac/state", HTTP_GET,     handleState);
  server.on("/net/info", HTTP_GET,     handleNetInfo);
  server.onNotFound(handleNotFound);

  server.begin();

#if ENABLE_HEARTBEAT
  // 랜덤 시드 초기화 및 첫 하트비트 스케줄
  randomSeed(ESP.getChipId() ^ micros());
  scheduleNextHeartbeat(millis());
#endif
}

// ---------------------------
// Loop
// ---------------------------
void loop() {
  server.handleClient();
  MDNS.update();

  if (millis() - g_lastMdnsAnnounce >= MDNS_ANNOUNCE_MS) {
    MDNS.announce();
    g_lastMdnsAnnounce = millis();
  }

  updateDhtIfNeeded();
#if ENABLE_HEARTBEAT
  sendHeartbeatIfDue();
#endif
  handleUdpQuery();
  // 브로드캐스트 질의 수신 후 상태 푸시 스케줄 처리
  pushStatusToBackend();

  static uint32_t last = 0;
  if (millis() - last > 100) {
    last = millis();
    updateStatusLeds();
  }
  // 주기적 양보로 WDT 예방 및 WiFi 스택 처리 보장
  yield();
}
