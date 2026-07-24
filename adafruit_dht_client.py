import time
import socket
import json
import datetime
import board
import adafruit_dht

dht_device = adafruit_dht.DHT22(board.D26)

SERVER_IP = "10.192.137.117"
PORT = 8765

try:
    while True:
        try:
            temperature = dht_device.temperature
            humidity = dht_device.humidity

            if temperature is not None and humidity is not None:
                print(f"Temperature: {temperature:.1f} ℃")
                print(f"Humidity: {humidity:.1f} %")

                data = {
                    "time": str(datetime.datetime.now()),
                    "temperature": temperature,
                    "humidity": humidity
                }

                json_data = json.dumps(data)

                with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
                    sock.connect((SERVER_IP, PORT))
                    sock.send(json_data.encode("utf-8"))

                print("データ送信完了")

            else:
                print("センサ値を取得できませんでした")

        except RuntimeError as e:
            print(f"読み取りエラー: {e}")

        time.sleep(3)

except KeyboardInterrupt:
    print("終了します")
    dht_device.exit()