package com.example.sensor_androidapp

import android.graphics.Color
import android.os.Bundle
import android.util.Log
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.ListView
import android.widget.TextView
import android.widget.Toast
import androidx.activity.ComponentActivity
import android.app.AlertDialog
import androidx.lifecycle.lifecycleScope
import com.github.mikephil.charting.charts.LineChart
import com.github.mikephil.charting.components.YAxis
import com.github.mikephil.charting.components.XAxis
import com.github.mikephil.charting.components.Legend
import com.github.mikephil.charting.data.Entry
import com.github.mikephil.charting.data.LineData
import com.github.mikephil.charting.data.LineDataSet
import com.github.mikephil.charting.formatter.IndexAxisValueFormatter
import kotlinx.coroutines.launch
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Body
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.delay
import kotlinx.coroutines.Job
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

data class SensorData(
    val timestamp: String,
    val temperature: Float,
    val humidity: Float
)

data class AddDataRequest(
    val timestamp: String,
    val temperature: Float,
    val humidity: Float
)

data class AddDataResponse(
    val status: String? = null,
    val error: String? = null
)

interface ApiService {
    @GET("api/data")
    suspend fun getSensorData(): List<SensorData>

    @POST("api/data")
    suspend fun addSensorData(@Body request: AddDataRequest): AddDataResponse
}

class MainActivity : ComponentActivity() {

    private lateinit var textAvgTemp: TextView
    private lateinit var textAvgHumid: TextView
    private lateinit var sensorListView: ListView
    private lateinit var sensorChart: LineChart
    private lateinit var btnLoadMore: Button
    private lateinit var btnManualInput: Button
    private lateinit var btnRefresh: Button

    // 接続中のIPアドレスを保持する
    private var currentIpAddress: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        // UIパーツをXMLから紐付け
        textAvgTemp = findViewById(R.id.textAvgTemp)
        textAvgHumid = findViewById(R.id.textAvgHumid)
        sensorListView = findViewById(R.id.sensorListView)
        sensorChart = findViewById(R.id.sensorChart)
        btnLoadMore = findViewById(R.id.btnLoadMore)
        btnManualInput = findViewById(R.id.btnManualInput)
        btnRefresh = findViewById(R.id.btnRefresh)

        // グラフの初期設定
        initChartSettings()

        // 更新ボタンのクリック設定
        btnRefresh.setOnClickListener {
            currentIpAddress?.let { ip ->
                fetchRealTimeData(ip)
            } ?: Toast.makeText(this, "接続設定が完了していません", Toast.LENGTH_SHORT).show()
        }

        // 手動入力ボタンのクリック設定
        btnManualInput.setOnClickListener {
            currentIpAddress?.let { ip ->
                showAddDataDialog(ip)
            } ?: Toast.makeText(this, "接続設定が完了していません", Toast.LENGTH_SHORT).show()
        }

        // アプリ起動時にIPアドレス入力ダイアログを表示する
        showIpInputDialog()
    }

    private fun showIpInputDialog() {
        val inputEditText = EditText(this).apply {
            hint = "192.168.xx.xx"
            inputType = android.text.InputType.TYPE_CLASS_TEXT
            setPadding(50, 40, 50, 40)
        }

        AlertDialog.Builder(this)
            .setTitle("接続設定")
            .setMessage("接続したいデータのIPアドレスを入力してください")
            .setView(inputEditText)
            .setCancelable(false)
            .setPositiveButton("接続開始") { _, _ ->
                val ipAddress = inputEditText.text.toString().trim()
                if (ipAddress.isNotEmpty()) {
                    currentIpAddress = ipAddress
                    // 初回データを取得
                    fetchRealTimeData(ipAddress)
                } else {
                    Toast.makeText(this, "IPアドレスを入力してください", Toast.LENGTH_SHORT).show()
                    showIpInputDialog()
                }
            }
            .show()
    }

    private fun fetchRealTimeData(ipAddress: String) {
        val baseUrl = "http://$ipAddress:5001/"

        val retrofit = Retrofit.Builder()
            .baseUrl(baseUrl)
            .addConverterFactory(GsonConverterFactory.create())
            .build()

        val apiService = retrofit.create(ApiService::class.java)

        lifecycleScope.launch {
            try {
                val rawDataList = apiService.getSensorData()

                if (rawDataList.isEmpty()) {
                    Toast.makeText(this@MainActivity, "データが空です", Toast.LENGTH_SHORT).show()
                    return@launch
                }

                // 日付が新しい順（降順）に並び替える
                val dataList = rawDataList.sortedByDescending { it.timestamp }

                val avgTemp = dataList.map { it.temperature }.average().toFloat()
                val avgHumid = dataList.map { it.humidity }.average().toFloat()

                textAvgTemp.text = String.format("%.1f °C", avgTemp)
                textAvgHumid.text = String.format("%.1f %%", avgHumid)

                var showAllData = false
                if (dataList.size > 5) {
                    btnLoadMore.visibility = View.VISIBLE
                }

                val adapter = object : android.widget.BaseAdapter() {
                    override fun getCount(): Int {
                        return if (showAllData) dataList.size else kotlin.math.min(5, dataList.size)
                    }
                    override fun getItem(position: Int): Any = dataList[position]
                    override fun getItemId(position: Int): Long = position.toLong()

                    override fun getView(position: Int, convertView: View?, parent: android.view.ViewGroup?): View {
                        val view = convertView ?: layoutInflater.inflate(R.layout.list_item_sensor, parent, false)
                        val data = dataList[position]

                        val tvTimestamp: TextView = view.findViewById(R.id.itemTimestamp)
                        val tvTemp: TextView = view.findViewById(R.id.itemTemp)
                        val tvTempDiff: TextView = view.findViewById(R.id.itemTempDiff)
                        val tvHumid: TextView = view.findViewById(R.id.itemHumid)
                        val tvHumidDiff: TextView = view.findViewById(R.id.itemHumidDiff)

                        tvTimestamp.text = data.timestamp
                        tvTemp.text = String.format("%.1f°C", data.temperature)
                        tvHumid.text = String.format("%.1f%%", data.humidity)

                        val diffTemp = data.temperature - avgTemp
                        val diffHumid = data.humidity - avgHumid

                        if (diffTemp >= 0) {
                            tvTempDiff.text = String.format("(+%.1f)", diffTemp)
                            tvTempDiff.setTextColor(Color.parseColor("#D32F2F"))
                        } else {
                            tvTempDiff.text = String.format("(%.1f)", diffTemp)
                            tvTempDiff.setTextColor(Color.parseColor("#1976D2"))
                        }

                        if (diffHumid >= 0) {
                            tvHumidDiff.text = String.format("(+%.1f)", diffHumid)
                            tvHumidDiff.setTextColor(Color.parseColor("#D32F2F"))
                        } else {
                            tvHumidDiff.text = String.format("(%.1f)", diffHumid)
                            tvHumidDiff.setTextColor(Color.parseColor("#1976D2"))
                        }

                        return view
                    }
                }

                sensorListView.adapter = adapter

                btnLoadMore.setOnClickListener {
                    showAllData = true
                    adapter.notifyDataSetChanged()
                    btnLoadMore.visibility = View.GONE
                }

                setupNativeChart(dataList)

            } catch (e: Exception) {
                Log.e("MainActivity", "通信エラー", e)
                Toast.makeText(this@MainActivity, "接続失敗: IPアドレスが正しいか確認してください", Toast.LENGTH_LONG).show()
                // 接続に失敗した場合は保持しているIPをクリアし、再入力を促す
                currentIpAddress = null
                showIpInputDialog()
            }
        }
    }

    private fun initChartSettings() {
        sensorChart.apply {
            description.isEnabled = false
            setTouchEnabled(true)
            isDragEnabled = true      // スクロールを有効にする
            isScaleXEnabled = true   // 拡大を有効にする
            isScaleYEnabled = false
            setPinchZoom(false)

            // 色の説明
            legend.apply {
                verticalAlignment = Legend.LegendVerticalAlignment.TOP
                horizontalAlignment = Legend.LegendHorizontalAlignment.RIGHT
                orientation = Legend.LegendOrientation.HORIZONTAL
                setDrawInside(true) // グラフの中に描画
                yOffset = 10f
                xOffset = 10f
                textColor = Color.parseColor("#666666")
            }

            extraTopOffset = 30f
            extraBottomOffset = 50f
        }

        sensorChart.xAxis.apply {
            position = XAxis.XAxisPosition.BOTTOM
            labelRotationAngle = -45f
            setAvoidFirstLastClipping(true)
            textColor = Color.parseColor("#666666")
            textSize = 10f
            setDrawGridLines(true)
            gridColor = Color.parseColor("#E0E0E0")
            gridLineWidth = 1f
        }

        sensorChart.axisLeft.apply {
            textColor = Color.parseColor("#FF5252")
            setDrawGridLines(true)
            enableGridDashedLine(10f, 10f, 0f)
            gridColor = Color.parseColor("#E0E0E0")
        }

        sensorChart.axisRight.apply {
            isEnabled = true
            textColor = Color.parseColor("#448AFF")
            setDrawGridLines(false)
        }
    }

    private fun setupNativeChart(dataList: List<SensorData>) {
        val chartDataList = dataList.reversed()
        val tempEntries = ArrayList<Entry>()
        val humidEntries = ArrayList<Entry>()
        val labels = ArrayList<String>()

        chartDataList.forEachIndexed { index, data ->
            tempEntries.add(Entry(index.toFloat(), data.temperature))
            humidEntries.add(Entry(index.toFloat(), data.humidity))
            val shortLabel = if (data.timestamp.length >= 19) data.timestamp.substring(11, 19) else data.timestamp
            labels.add(shortLabel)
        }

        val tempDataSet = LineDataSet(tempEntries, "気温 (°C)").apply {
            color = Color.parseColor("#FF5252")
            setCircleColor(Color.parseColor("#FF5252"))
            lineWidth = 2.5f
            circleRadius = 4f
            setDrawCircleHole(true)
            circleHoleRadius = 2f
            axisDependency = YAxis.AxisDependency.LEFT
            mode = LineDataSet.Mode.CUBIC_BEZIER
            setDrawValues(false)
        }

        val humidDataSet = LineDataSet(humidEntries, "湿度 (%)").apply {
            color = Color.parseColor("#448AFF")
            setCircleColor(Color.parseColor("#448AFF"))
            lineWidth = 2.5f
            circleRadius = 4f
            setDrawCircleHole(true)
            circleHoleRadius = 2f
            axisDependency = YAxis.AxisDependency.RIGHT
            mode = LineDataSet.Mode.CUBIC_BEZIER
            setDrawValues(false)
        }

        sensorChart.data = LineData(tempDataSet, humidDataSet)

        // ラベルを更新
        sensorChart.xAxis.valueFormatter = IndexAxisValueFormatter(labels)
        sensorChart.xAxis.setLabelCount(5, false)

        // 表示範囲を5件に制限し、右端へ移動
        sensorChart.setVisibleXRangeMaximum(5f)
        if (chartDataList.size > 5) {
            sensorChart.moveViewToX((chartDataList.size - 5).toFloat())
        }

        val customMarker = object : com.github.mikephil.charting.components.MarkerView(this, R.layout.chart_marker) {
            private val tvTimestamp: TextView = findViewById(R.id.markerTimestamp)
            private val tvValue: TextView = findViewById(R.id.markerValue)

            override fun refreshContent(e: Entry?, highlight: com.github.mikephil.charting.highlight.Highlight?) {
                if (e == null || highlight == null) return
                val index = e.x.toInt()
                if (index in dataList.indices) {
                    val data = dataList[index]
                    tvTimestamp.text = data.timestamp
                    if (highlight.axis == YAxis.AxisDependency.LEFT) {
                        tvValue.text = String.format("気温: %.1f°C", e.y)
                        tvValue.setTextColor(Color.parseColor("#FF8A80"))
                    } else {
                        tvValue.text = String.format("湿度: %.1f%%", e.y)
                        tvValue.setTextColor(Color.parseColor("#82B1FF"))
                    }
                }
                super.refreshContent(e, highlight)
            }

            override fun getOffset(): com.github.mikephil.charting.utils.MPPointF {
                return com.github.mikephil.charting.utils.MPPointF((-(width / 2)).toFloat(), (-height).toFloat())
            }
        }
        sensorChart.marker = customMarker

        sensorChart.invalidate()
    }
    // データ追加ダイアログの表示と送信処理
    private fun showAddDataDialog(ipAddress: String) {
        val layout = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            setPadding(60, 40, 60, 10)
        }

        // スマホの設定時刻（日本時間など）を取得して初期値にする
        val sdf = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
        sdf.timeZone = TimeZone.getDefault()
        val currentDateTime = sdf.format(Date())

        val editTimestamp = EditText(this).apply {
            hint = "日時 例: 2026-06-27 11:00:00"
            setText(currentDateTime) // 自動で現在時刻を入力
            inputType = android.text.InputType.TYPE_CLASS_TEXT
        }

        val editTemp = EditText(this).apply {
            hint = "気温 (°C) 例: 25.5"
            inputType = android.text.InputType.TYPE_CLASS_NUMBER or android.text.InputType.TYPE_NUMBER_FLAG_DECIMAL
        }

        val editHumid = EditText(this).apply {
            hint = "湿度 (%) 例: 60.0"
            inputType = android.text.InputType.TYPE_CLASS_NUMBER or android.text.InputType.TYPE_NUMBER_FLAG_DECIMAL
        }

        layout.addView(editTimestamp)
        layout.addView(editTemp)
        layout.addView(editHumid)

        AlertDialog.Builder(this)
            .setTitle("手動データ追加")
            .setMessage("各項目を入力してください")
            .setView(layout)
            .setPositiveButton("追加") { _, _ ->
                val timeStr = editTimestamp.text.toString().trim()
                val tempStr = editTemp.text.toString().trim()
                val humidStr = editHumid.text.toString().trim()

                if (timeStr.isEmpty() || tempStr.isEmpty() || humidStr.isEmpty()) {
                    Toast.makeText(this, "エラー: すべての項目を入力してください！", Toast.LENGTH_LONG).show()
                    return@setPositiveButton
                }

                try {
                    val temp = tempStr.toFloat()
                    val humid = humidStr.toFloat()

                    // API経由でデータを送信
                    postSensorData(ipAddress, timeStr, temp, humid)

                } catch (e: NumberFormatException) {
                    Toast.makeText(this, "エラー: 気温と湿度は数値で入力してください", Toast.LENGTH_SHORT).show()
                }
            }
            .setNegativeButton("キャンセル", null)
            .show()
    }

    // 実際のリクエスト送信処理
    private fun postSensorData(ipAddress: String, timestamp: String, temp: Float, humid: Float) {
        val baseUrl = "http://$ipAddress:5001/"
        val retrofit = Retrofit.Builder()
            .baseUrl(baseUrl)
            .addConverterFactory(GsonConverterFactory.create())
            .build()

        val apiService = retrofit.create(ApiService::class.java)

        lifecycleScope.launch {
            try {
                val response = apiService.addSensorData(AddDataRequest(timestamp, temp, humid))
                if (response.status == "success") {
                    Toast.makeText(this@MainActivity, "${timestamp} にデータを追加しました！", Toast.LENGTH_SHORT).show()
                    // 即座に一覧を最新化
                    fetchRealTimeData(ipAddress)
                } else {
                    Toast.makeText(this@MainActivity, "追加失敗: ${response.error}", Toast.LENGTH_SHORT).show()
                }
            } catch (e: Exception) {
                Log.e("MainActivity", "送信エラー", e)
                Toast.makeText(this@MainActivity, "通信エラー: データを追加できませんでした", Toast.LENGTH_SHORT).show()
            }
        }
    }
}