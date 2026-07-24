import csv
from datetime import datetime
import math
import os

from flask import Flask, jsonify, render_template, request

try:
    import fcntl
except ImportError:
    # Windowsなどfcntlを利用できない環境でもアプリを起動できるようにする。
    fcntl = None


app = Flask(__name__)

# このPythonファイルと同じフォルダへCSVを保存する。
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CSV_PATH = os.path.join(BASE_DIR, "sensor_data.csv")
CSV_HEADER = ["timestamp", "temperature", "humidity"]


def lock_file(csv_file, lock_type):
    """fcntlが利用できる環境ではCSVファイルをロックする。"""
    if fcntl is not None:
        fcntl.flock(csv_file.fileno(), lock_type)


def unlock_file(csv_file):
    if fcntl is not None:
        fcntl.flock(csv_file.fileno(), fcntl.LOCK_UN)


def ensure_csv_file():
    """CSVが存在しない場合は、ヘッダー付きで作成する。"""
    with open(CSV_PATH, "a+", newline="", encoding="utf-8") as csv_file:
        lock_file(csv_file, fcntl.LOCK_EX if fcntl is not None else None)
        try:
            csv_file.seek(0, os.SEEK_END)
            if csv_file.tell() == 0:
                csv.writer(csv_file).writerow(CSV_HEADER)
                csv_file.flush()
        finally:
            unlock_file(csv_file)


def append_sensor_data(timestamp, temperature, humidity):
    """排他ロック中にCSVへセンサーデータを1行追加する。"""
    ensure_csv_file()

    with open(CSV_PATH, "a+", newline="", encoding="utf-8") as csv_file:
        lock_file(csv_file, fcntl.LOCK_EX if fcntl is not None else None)
        try:
            # 既存ファイルの末尾に改行がなくても、最終行を壊さずに追記する。
            csv_file.seek(0, os.SEEK_END)
            if csv_file.tell() > 0:
                csv_file.seek(csv_file.tell() - 1)
                if csv_file.read(1) not in ("\n", "\r"):
                    csv_file.write("\n")

            csv_file.seek(0, os.SEEK_END)
            csv.writer(csv_file).writerow([timestamp, temperature, humidity])
            csv_file.flush()
        finally:
            unlock_file(csv_file)


@app.after_request
def add_cors_headers(response):
    """iOS以外のWebクライアントからもAPIを呼び出せるようにする。"""
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type"
    return response


@app.route("/", methods=["GET"])
def index():
    return render_template("Devpro3_html.html")


@app.route("/api/data", methods=["GET"])
def get_data_api():
    """CSVに保存されたデータをJSON配列として返す。"""
    ensure_csv_file()
    data_list = []

    try:
        with open(CSV_PATH, mode="r", newline="", encoding="utf-8") as csv_file:
            lock_file(csv_file, fcntl.LOCK_SH if fcntl is not None else None)
            try:
                """reader = csv.DictReader(csv_file)
                for row in reader:
                    try:
                        data_list.append({
                            "timestamp": row["timestamp"],
                            "temperature": float(row["temperature"]),
                            "humidity": float(row["humidity"]),
                        })
                    except (KeyError, TypeError, ValueError):
                        # 壊れた行があっても、正常な行は取得できるようにする。"""
                # ヘッダーの有無や余分な列があるCSVでも読めるように、先頭3列だけを使う。
                for row in csv.reader(csv_file):
                    if len(row) < 3 or row[:3] == CSV_HEADER:
                        continue
                    try:
                        data_list.append({
                            "timestamp": row[0],
                            "temperature": float(row[1]),
                            "humidity": float(row[2]),
                        })
                    except ValueError:
                        # 壊れた行があっても、正常な行は取得できるようにする。
                        continue
            finally:
                unlock_file(csv_file)

        return jsonify(data_list), 200
    except OSError as error:
        app.logger.exception("CSVの読み込みに失敗しました: %s", error)
        return jsonify({"error": "CSVファイルを読み込めませんでした。"}), 500


@app.route("/api/data", methods=["POST"])
def post_data_api():
    """iOSアプリから受信した手動追加データをCSVへ保存する。"""
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"error": "JSON形式のリクエスト本文を送信してください。"}), 400

    required_keys = ("timestamp", "temperature", "humidity")
    missing_keys = [key for key in required_keys if key not in data]
    if missing_keys:
        return jsonify({"error": f"必須キーがありません: {', '.join(missing_keys)}"}), 400

    timestamp = data["timestamp"]
    if not isinstance(timestamp, str):
        return jsonify({"error": "timestamp は YYYY-MM-DD HH:mm:ss 形式の文字列で指定してください。"}), 400

    try:
        timestamp = datetime.strptime(timestamp, "%Y-%m-%d %H:%M:%S").strftime(
            "%Y-%m-%d %H:%M:%S"
        )
    except ValueError:
        return jsonify({"error": "timestamp は YYYY-MM-DD HH:mm:ss 形式で指定してください。"}), 400

    try:
        # boolはfloat(True) == 1.0となるため、数値としては受け付けない。
        if isinstance(data["temperature"], bool) or isinstance(data["humidity"], bool):
            raise ValueError

        temperature = float(data["temperature"])
        humidity = float(data["humidity"])
        if not math.isfinite(temperature) or not math.isfinite(humidity):
            raise ValueError
    except (TypeError, ValueError):
        return jsonify({"error": "temperature と humidity は有効な数値で指定してください。"}), 400

    try:
        append_sensor_data(timestamp, temperature, humidity)
        app.logger.info("CSVへ保存しました: %s, %s, %s", timestamp, temperature, humidity)
        return jsonify({"status": "success"}), 201
    except OSError as error:
        app.logger.exception("CSVへの保存に失敗しました: %s", error)
        return jsonify({"error": "CSVファイルへの保存に失敗しました。"}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001, debug=True)
