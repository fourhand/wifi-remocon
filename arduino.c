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
#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>
#include <ESP8266mDNS.h>
#include <IRremoteESP8266.h>
#include <IRsend.h>
#include <ir_Samsung.h>
#include <DHT.h>
#include <WiFiUdp.h>

// ---------------------------
// 기본 설정
// ---------------------------
static const char* HOST = "f4-ac-02";
static const uint16_t HTTP_PORT = 80;
static const uint16_t UDP_PORT  = 4210;
static const unsigned long MDNS_ANNOUNCE_MS = 120000;

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

  ac.send();

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
unsigned long lastBeat = 0;
void sendHeartbeat() {
  if (millis() - lastBeat < 5000) return;
  lastBeat = millis();

  String p = String("{\"id\":\"") + HOST +
             "\",\"ip\":\"" + WiFi.localIP().toString() +
             "\",\"port\":" + HTTP_PORT + "}";

  udp.beginPacket(IPAddress(255,255,255,255), UDP_PORT);
  udp.write((const uint8_t*)p.c_str(), p.length());
  udp.endPacket();
}

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

  String resp = String("{\"id\":\"") + HOST +
                "\",\"domain\":\"" + HOST + ".local" +
                "\",\"ip\":\"" + WiFi.localIP().toString() +
                "\",\"port\":" + HTTP_PORT + "}";

  udp.beginPacket(udp.remoteIP(), udp.remotePort());
  udp.write((const uint8_t*)resp.c_str(), resp.length());
  udp.endPacket();
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

  dht.begin();
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
  sendHeartbeat();
  handleUdpQuery();

  static uint32_t last = 0;
  if (millis() - last > 100) {
    last = millis();
    updateStatusLeds();
  }
}
