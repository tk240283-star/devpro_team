import socket
import datetime
import os
import json
import threading #2

PORT = 8765
BUFFER_SIZE = 1024
SAVE_FILE = "sensor_data.csv"
IP_ADDRESS = "0.0.0.0"
csv_lock = threading.Lock() #2

def start_server():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind((IP_ADDRESS, PORT))
        s.listen(1)
        
        print(f"Server started on port {PORT}. Waiting...")

        while True:
            conn, addr = s.accept()
            with conn:
                data = conn.recv(BUFFER_SIZE)
                if not data:
                    break
                
                message = data.decode('utf-8')
                now = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')

                try:
                    json_data = json.loads(message)
                    
                    # リスト形式で送られてきた場合の対応
                    if isinstance(json_data, list):
                        json_data = json_data[0]
                        
                    temperature = json_data.get("temperature", "")
                    humidity = json_data.get("humidity", "")
                except json.JSONDecodeError:
                    temperature = "error"
                    humidity = "error"

                print(f"[{now}] Temp: {temperature}, Hum: {humidity}")

                # CSVへの保存 #2
                with csv_lock:
                    file_exists = os.path.isfile(SAVE_FILE)

                    with open(SAVE_FILE, mode="a", encoding="utf-8") as f:
                        if not file_exists:
                            f.write("timestamp,temperature,humidity\n")

                        f.write(f"{now},{temperature},{humidity}\n")

if __name__ == "__main__":
    start_server()