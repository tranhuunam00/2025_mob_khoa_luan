import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;

class ChartScreen extends StatefulWidget {
  final BluetoothCharacteristic characteristic;

  const ChartScreen({super.key, required this.characteristic});

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  late StreamSubscription<List<int>> sub;

  final List<FlSpot> xList = [];
  final List<FlSpot> yList = [];
  final List<FlSpot> zList = [];

  double t = 0;

  static const int maxPoints = 200; // viewport hiển thị
  static const int sendBatch = 100; // gửi server mỗi 100 mẫu
  static const int resetLimit = 2000; // tránh tràn bộ nhớ

  final List<Map<String, dynamic>> buffer = [];

  int receivedSamples = 0;
  int sentSamples = 0;

  Timer? chartTimer;
  bool needRepaint = false;

  @override
  void initState() {
    super.initState();

    widget.characteristic.setNotifyValue(true);
    sub = widget.characteristic.lastValueStream.listen(handleBLE);

    // 20 FPS
    chartTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (needRepaint && mounted) {
        setState(() {});
        needRepaint = false;
      }
    });
  }

  @override
  void dispose() {
    chartTimer?.cancel();
    sub.cancel();
    widget.characteristic.setNotifyValue(false);
    super.dispose();
  }

  // ========== SEND ==============
  Future<void> send(List<Map<String, dynamic>> values) async {
    final url = Uri.parse("http://222.255.214.218:3001/iot");
    final body = jsonEncode({"data": values});

    try {
      final res = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: body,
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        sentSamples += values.length;
        print("✔ Sent ${values.length}");
      } else {
        print("❌ Server error ${res.statusCode}");
      }
    } catch (e) {
      print("❌ Send error $e");
    }

    if (mounted) setState(() {});
  }

  // ========== PARSE ==========
  List<double> parse(List<int> d) {
    List<double> out = [];
    for (int i = 0; i + 2 < d.length; i += 3) {
      int sign = d[i] == 1 ? 1 : -1;
      double v = sign * (d[i + 1] + d[i + 2] / 100.0);
      out.add(v);
    }
    return out;
  }

  // ========== HANDLE BLE ==========
  void handleBLE(List<int> raw) {
    receivedSamples++;

    final parsed = parse(raw);

    if (parsed.length >= 3) {
      // ❗ KHÔNG XÓA PHẦN TỬ ĐẦU – KHÔNG REMOVEAT
      xList.add(FlSpot(t, parsed[0]));
      yList.add(FlSpot(t, parsed[1]));
      zList.add(FlSpot(t, parsed[2]));

      t++;
      needRepaint = true;
    }

    // BUFFER CHO SERVER
    buffer.add({
      "createdAt": DateTime.now().toIso8601String(),
      "value": parsed.join(", "),
      "user": 1
    });

    // RESET TRÁNH TRÀN RAM
    if (receivedSamples >= resetLimit) {
      xList.clear();
      yList.clear();
      zList.clear();
      t = 0;
      receivedSamples = 0;
      print("⚠ Chart reset to avoid memory overflow");
    }

    // GỬI SERVER
    if (buffer.length >= sendBatch) {
      send(List<Map<String, dynamic>>.from(buffer));
      buffer.clear();
    }
  }

  // ========== CHART ==========
  Widget buildChart() {
    final double minX = (t - maxPoints).clamp(0, double.infinity);
    final double maxX = t;

    return Column(
      children: [
        SizedBox(
          height: 260,
          child: LineChart(
            LineChartData(
              minX: minX,
              maxX: maxX,
              minY: -2,
              maxY: 2,

              // KHÓA Y để không scale → đảm bảo không nháy
              baselineY: 0,
              lineTouchData: LineTouchData(enabled: false),

              lineBarsData: [
                LineChartBarData(
                  spots: xList,
                  color: Colors.red,
                  isCurved: false,
                  barWidth: 2,
                  dotData: FlDotData(show: false),
                ),
                LineChartBarData(
                  spots: yList,
                  color: Colors.green,
                  isCurved: false,
                  barWidth: 2,
                  dotData: FlDotData(show: false),
                ),
                LineChartBarData(
                  spots: zList,
                  color: Colors.blue,
                  isCurved: false,
                  barWidth: 2,
                  dotData: FlDotData(show: false),
                ),
              ],

              gridData: FlGridData(show: true),
              borderData: FlBorderData(show: true),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            LegendItem(color: Colors.red, text: "X"),
            SizedBox(width: 16),
            LegendItem(color: Colors.green, text: "Y"),
            SizedBox(width: 16),
            LegendItem(color: Colors.blue, text: "Z"),
          ],
        ),
        const SizedBox(height: 8),
        const Text("Dữ liệu cảm biến gia tốc",
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      ],
    );
  }

  // ========== UI MAIN ==========
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Realtime Accelerometer Chart")),
      body: Column(
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: buildChart(),
          ),
          const SizedBox(height: 16),
          Text("📥 Nhận: $receivedSamples mẫu",
              style: const TextStyle(fontSize: 16)),
          Text("📤 Đã gửi: $sentSamples mẫu",
              style: const TextStyle(fontSize: 16, color: Colors.blue)),
        ],
      ),
    );
  }
}

class LegendItem extends StatelessWidget {
  final Color color;
  final String text;

  const LegendItem({super.key, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(text)
      ],
    );
  }
}
