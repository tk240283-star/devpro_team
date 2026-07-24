from flask import Flask, render_template, jsonify, request
import csv
from datetime import datetime
import portalocker  # Windows対応のファイルロックライブラリ

app = Flask(__name__)

@app.route("/", methods=["GET"])
def index():
    print("ブラウザからアクセスされたので、HTMLを表示するよ！")
    return render_template("Devpro3_work05_html.html")

@app.route("/api/data", methods=["GET"])
def get_data_api():
    print("Hello! (to Terminal)")
    data_list = []
    file_path = "work05/sensor_data.csv"

    print("csvを読み込むよ！")
    try:
        # portalocker.LOCK_SH (共有ロック) でファイルを開く
        with portalocker.Lock(file_path, mode='r', timeout=5, flags=portalocker.LOCK_SH, encoding='utf-8') as f:
            reader = csv.reader(f)
            next(reader, None)  # ヘッダーをスキップ

            for row in reader:
                if not row: continue
                date_str = row[0]
                temp = float(row[1])
                humid = float(row[2])
                data_list.append({"timestamp": date_str, "temperature": temp, "humidity": humid})

        return jsonify(data_list)
    except FileNotFoundError:
        print("csvファイルが見つからないよ！")
        return jsonify({"result": "error", "message": "CSVファイルが見つかりません"}), 404

@app.route("/api/data", methods=["POST"])
def post_data_api():
    print("アプリからデータを受信しました")
    data = request.get_json()

    try:
        temperature = float(data["temperature"])
        humidity = float(data["humidity"])
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        file_path = "work05/sensor_data.csv"

        # portalocker.LOCK_EX (排他ロック) でファイル追記
        with portalocker.Lock(file_path, mode='a', timeout=5, flags=portalocker.LOCK_EX, encoding='utf-8', newline='') as f:
            writer = csv.writer(f)
            writer.writerow([timestamp, temperature, humidity])
            f.flush()

        print(f"保存しました: {timestamp}, {temperature}, {humidity}")

        return jsonify({
            "result": "success",
            "message": "CSVへ保存しました"
        }), 200

    except Exception as e:
        print(e)
        return jsonify({
            "result": "error",
            "message": str(e)
        }), 400


if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5001, debug=True)