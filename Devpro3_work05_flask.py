from flask import Flask, render_template, jsonify, request
import csv
from datetime import datetime

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
        with open(file_path, mode='r', encoding='utf-8') as f:
            print("csvを読み込んだ結果を表示するね！")

            reader = csv.reader(f)
            next(reader)
        
            for row in reader:
                date_str = row[0]
                temp = float(row[1])
                humid = float(row[2])
                data_list.append({"timestamp":date_str, "temperature":temp, "humidity":humid})
                print(f"日付: {date_str}, 温度: {temp}, 湿度: {humid}")
        
        return jsonify(data_list)
    except FileNotFoundError:
        print("csvファイルが見つからないよ！")
    return "CSVファイルが見つかりません", 404 

@app.route("/api/data", methods=["POST"])
def post_data_api():
    print("アプリからデータを受信しました")

    data = request.get_json()

    try:
        temperature = float(data["temperature"])
        humidity = float(data["humidity"])

        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        file_path = "work05/sensor_data.csv"

        with open(file_path, mode="a", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow([timestamp, temperature, humidity])

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
    app.run(host = '0.0.0.0', port = 5001, debug=True)