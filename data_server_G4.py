import socket
import datetime
import os
import json
try:
    import fcntl #2
except ImportError:
    # Windowsなどfcntlを利用できない環境でもサーバを起動できるようにする。
    fcntl = None

PORT = 8765
BUFFER_SIZE = 1024
# このPythonファイルと同じフォルダのCSVへ保存する。（起動したフォルダに左右されないようにする。）
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SAVE_FILE = os.path.join(BASE_DIR, "sensor_data.csv")
IP_ADDRESS = "0.0.0.0"

def lock_file(csv_file, lock_type):
    """fcntlが利用できる環境ではCSVファイルをロックする。"""
    if fcntl is not None:
        fcntl.flock(csv_file.fileno(), lock_type)


def unlock_file(csv_file):
    if fcntl is not None:
        fcntl.flock(csv_file.fileno(), fcntl.LOCK_UN)

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
                    # データを送らずに切断されただけなので、サーバは止めずに次の接続を待つ。
                    continue
                
                message = data.decode('utf-8')
                now = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')

                try:
                    json_data = json.loads(message)

                    if isinstance(json_data, list):
                        json_data = json_data[0]

                    temperature = json_data.get("temperature", "")
                    humidity = json_data.get("humidity", "")
                    # どのセンサノードから届いたデータかを記録する。
                    node_id = json_data.get("node_id", "unknown")

                    # センサノードが測定した時刻を優先する。（受信時刻ではなく測定時刻を残す。）
                    measured = json_data.get("time", "")
                    if measured:
                        try:
                            now = datetime.datetime.fromisoformat(measured).strftime(
                                '%Y-%m-%d %H:%M:%S')
                        except ValueError:
                            # 時刻の形式が不正なら受信時刻のままにする。
                            pass
                except json.JSONDecodeError:
                    print(f"[{now}] JSONではないデータを受信したため保存しません。")
                    continue

                # 温度・湿度が欠けているデータは測定値ではないので保存しない。
                if temperature == "" or humidity == "":
                    print(f"[{now}] 温度・湿度が欠けているため保存しません。")
                    continue

                print(f"[{now}] Node: {node_id}  Temp: {temperature}, Hum: {humidity}")


                # CSVへの保存 #2
                file_exists = os.path.isfile(SAVE_FILE)
                """with open(SAVE_FILE, mode="a", encoding="utf-8") as f:
                    fcntl.flock(f, fcntl.LOCK_EX)

                    if not file_exists:
                        f.write("timestamp,temperature,humidity,node_id\n")

                    f.write(f"{now},{temperature},{humidity},{node_id}\n")

                    f.flush() 
                    fcntl.flock(f, fcntl.LOCK_UN)  """
                with open(SAVE_FILE, mode="a+", encoding="utf-8") as f:
                    lock_file(f, fcntl.LOCK_EX if fcntl is not None else None)
                    try:
                        if not file_exists:
                            f.write("timestamp,temperature,humidity\n")

                        # 既存ファイルの末尾に改行がなくても、最終行を壊さずに追記する。
                        f.seek(0, os.SEEK_END)
                        if f.tell() > 0:
                            f.seek(f.tell() - 1)
                            if f.read(1) not in ("\n", "\r"):
                                f.write("\n")

                        f.seek(0, os.SEEK_END)
                        f.write(f"{now},{temperature},{humidity}\n")

                        f.flush()
                    finally:
                        unlock_file(f)

if __name__ == "__main__":
    start_server()