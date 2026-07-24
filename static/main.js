window.onload = () => {
    // ページの読み込み完了後に処理を開始

    fetch('/api/data')
    // FlaskのAPIから温度・湿度データを取得

        .then(res => res.json())
        // APIから返されたJSONデータをJavaScriptで扱える形式に変換

        .then(data => {

            if (!data.length) {
                // データが存在しない場合はメッセージを表示して処理を終了
                return document.getElementById('status-msg').innerHTML = "データがありません。";
            }

            // テーブル表示用HTML、平均表示用HTML、グラフ用配列、日別平均計算用データを準備
            let tableHtml = "", avgHtml = "";
            const timeLabels = [], tempArray = [], humidArray = [], dailyData = {};

            // 取得したデータを1件ずつ処理
            data.forEach(row => {

                // テーブルへ表示するHTMLを作成
                tableHtml += `<tr><td>${row.timestamp}</td><td>${row.node_id}</td><td>${row.temperature}</td><td>${row.humidity}</td></tr>`;

                // グラフ表示用のデータを配列へ保存
                timeLabels.push(row.timestamp);
                tempArray.push(row.temperature);
                humidArray.push(row.humidity);

                // 日付のみを取得
                const dateStr = row.timestamp.split(' ')[0];

                // 日付ごとのデータが無ければ初期化
                if (!dailyData[dateStr])
                    dailyData[dateStr] = {
                        totalTemp: 0,
                        totalHumid: 0,
                        count: 0
                    };

                // 平均計算のため温度・湿度を加算
                dailyData[dateStr].totalTemp += row.temperature;
                dailyData[dateStr].totalHumid += row.humidity;

                // データ件数を加算
                dailyData[dateStr].count++;
            });

            // テーブルへ観測データを表示
            document.getElementById("table-body").innerHTML = tableHtml;

            // 日別平均の作成

            for (let dateKey in dailyData) {

                // 1日分のデータを取得
                const d = dailyData[dateKey];

                // 平均温度・平均湿度を計算
                const avgT = (d.totalTemp / d.count).toFixed(1);
                const avgH = (d.totalHumid / d.count).toFixed(1);

                // 日別平均表示用HTMLを作成
                avgHtml += `<div class="avg-row">${dateKey} 平均温度：${avgT}℃ ／ 平均湿度：${avgH}%</div>`;
            }

            // 日別平均を画面へ表示
            document.getElementById("daily-avg").innerHTML = avgHtml;

            // 折れ線グラフを作成

            new Chart(document.getElementById("myChart").getContext("2d"), {

                // グラフ種類（折れ線）
                type: "line",

                data: {

                    // 横軸に日時を設定
                    labels: timeLabels,

                    // 温度と湿度の2種類のデータを表示
                    datasets: [
                        { label: "温度", data: tempArray, borderColor: "red", fill: false },
                        { label: "湿度", data: humidArray, borderColor: "blue", fill: false }
                    ]
                },

                options: {

                    // マウスカーソルに最も近いデータを選択
                    interaction: {
                        mode: "nearest",
                        intersect: true,
                        axis: "xy"
                    },

                    plugins: {

                        tooltip: {

                            // 色付き四角を非表示
                            displayColors: false,

                            callbacks: {

                                // ツールチップのタイトルに日時を表示
                                title: ctx => `日時：${ctx[0].label}`,

                                // ツールチップへ詳細情報を表示
                                label: ctx => {

                                    const label = ctx.dataset.label;
                                    const val = ctx.parsed.y;

                                    // 日付を取得
                                    const dateKey = ctx.label.split(" ")[0];

                                    const d = dailyData[dateKey];

                                    // 温度データの場合
                                    if (label === "温度") {

                                        const avg = d.totalTemp / d.count;

                                        const diff = val - avg;

                                        return [
                                            `温度：${val.toFixed(1)}℃`,
                                            `平均温度：${avg.toFixed(1)}℃`,
                                            `平均との差：${diff >= 0 ? "+" : ""}${diff.toFixed(1)}℃`
                                        ];
                                    }

                                    // 湿度データの場合
                                    if (label === "湿度") {

                                        const avg = d.totalHumid / d.count;

                                        const diff = val - avg;

                                        return [
                                            `湿度：${val.toFixed(1)}%`,
                                            `平均湿度：${avg.toFixed(1)}%`,
                                            `平均との差：${diff >= 0 ? "+" : ""}${diff.toFixed(1)}%`
                                        ];
                                    }

                                    return `${label}：${val}`;
                                }
                            }
                        }
                    }
                }
            });

            // ==========================
            // 背景・エフェクト表示
            // ==========================

            // 最新データを取得
            const last = data[data.length - 1];

            // 現在時刻を取得
            const hour = new Date().getHours();

            // 夜間かどうかを判定
            const isNight = (hour >= 20 || hour <= 4);

            // 気温と時間帯に応じて背景色を変更
            document.body.style.backgroundColor = isNight
                ? (last.temperature >= 30 ? "darkred" : last.temperature <= 15 ? "midnightblue" : "dimgray")
                : (last.temperature >= 30 ? "tomato" : last.temperature <= 15 ? "lightcyan" : "skyblue");

            // 気温15℃以下なら雲と風、それ以外は太陽を表示
            document.getElementById("effect-area").innerHTML = last.temperature <= 15
                ? `<div class="cloud" style="top:30px; left:0;">☁️</div><div class="cloud" style="top:120px; left:250px; animation-delay:8s;">☁️</div><div class="cloud" style="top:220px; left:500px; animation-delay:15s;">☁️</div><div class="wind" style="top:350px; width:220px;"></div><div class="wind" style="top:450px; width:320px;"></div>`
                : `<div class="sun"></div>`;

            // 最新の観測データを画面上部へ表示
            document.getElementById("status-msg").innerHTML =
                `最新データ（${last.timestamp}）：温度 ${last.temperature}℃ / 湿度 ${last.humidity}%`;

        })

        // データ取得に失敗した場合の処理
        .catch(() =>
            document.getElementById("status-msg").innerHTML = "エラーが起きました。"
        );
};