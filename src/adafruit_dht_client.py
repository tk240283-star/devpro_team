import time
import socket
import json
import datetime
import board
import adafruit_dht

dht_device = adafruit_dht.DHT22(board.D26)

SERVER_IP = "10.192.137.117"
PORT = 8765

def get_node_id():
    """Raspberry Piのシリアル番号をセンサノードの識別子として使う。

    シリアル番号はハードウェア固有なので、ノードごとの設定が要らず、重複もしない。
    取得できない環境では "unknown" を返し、送信自体は続けられるようにする。
    """
    try:
        with open("/proc/cpuinfo", encoding="utf-8") as f:
            for line in f:
                if line.startswith("Serial"):
                    return line.split(":")[1].strip()
    except OSError:
        pass
    return "unknown"


NODE_ID = get_node_id()

try:
    while True:
        try:
            temperature = dht_device.temperature
            humidity = dht_device.humidity

            if temperature is None or humidity is None:
                
                print("温湿度を取得できませんでした。次回の測定へ移ります。")
                time.sleep(5)
                continue

            now = datetime.datetime.now()

            print(f"Last valid input: {now}")
            print(f"Temperature: {temperature:.1f} ℃")
            print(f"Humidity: {humidity:.1f} %")

            data = {
                "node_id":NODE_ID,
                "time": str(datetime.datetime.now()),
                "temperature": temperature,
                "humidity": humidity
            }

            json_data = json.dumps(data)

            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
                sock.connect((SERVER_IP, PORT))
                sock.send(json_data.encode("utf-8"))

            print("データ送信完了")

        except RuntimeError as e:
            print(f"センサ読み取りエラー: {e}")
            print("このデータは送信せず、次回の測定を行います。")


        except Exception as e:
            print(f"エラー: {e}")

        time.sleep(5)

except KeyboardInterrupt:
    print("終了します")
    dht_device.exit()