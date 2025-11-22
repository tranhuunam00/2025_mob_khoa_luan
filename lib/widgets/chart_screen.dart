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

  static const int maxPoints = 100; // chỉ hiển thị 100 điểm
  static const int sendBatch = 500; // gửi server mỗi 50 mẫu
  static const int resetChartLimit = 2000; // reset chart tránh tràn RAM

  final List<Map<String, dynamic>> buffer = [];

  int receivedSamples = 0;
  int sentSamples = 0;

  @override
  void initState() {
    super.initState();
    widget.characteristic.setNotifyValue(true);
    sub = widget.characteristic.lastValueStream.listen(handleValue);
  }

  @override
  void dispose() {
    sub.cancel();
    widget.characteristic.setNotifyValue(false);
    super.dispose();
  }

  // ========== SEND TO SERVER ==========
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
        print("✔ SERVER OK: ${res.statusCode} (${values.length} samples)");
      } else {
        print("❌ SERVER ERROR: ${res.statusCode}");
      }
    } catch (e) {
      print("❌ Send error: $e");
    }

    if (mounted) setState(() {});
  }

  // ========== PARSE ACCEL ==========
  List<double> parse(List<int> data) {
    List<double> out = [];
    for (int i = 0; i + 2 < data.length; i += 3) {
      int sign = data[i] == 1 ? 1 : -1;
      double v = sign * (data[i + 1] + data[i + 2] / 100.0);
      out.add(v);
    }
    return out;
  }

  // ========== HANDLE NOTIFY ==========
  void handleValue(List<int> raw) {
    receivedSamples++;

    final parsed = parse(raw);
    if (parsed.length >= 3) {
      xList.add(FlSpot(t, parsed[0]));
      yList.add(FlSpot(t, parsed[1]));
      zList.add(FlSpot(t, parsed[2]));

      if (xList.length > maxPoints) xList.removeAt(0);
      if (yList.length > maxPoints) yList.removeAt(0);
      if (zList.length > maxPoints) zList.removeAt(0);

      t++;
    }

    buffer.add({
      "createdAt": DateTime.now().toIso8601String(),
      "value": parsed.join(", "),
      "user": 1
    });

    // ==== RESET CHART AVOID MEMORY LEAK ====
    if (receivedSamples >= resetChartLimit) {
      xList.clear();
      yList.clear();
      zList.clear();
      t = 0;
      receivedSamples = 0;
      print("⚠ RESET chart to avoid memory overflow");
    }

    // ==== SEND SERVER ====
    if (buffer.length >= sendBatch) {
      send(List<Map<String, dynamic>>.from(buffer));
      buffer.clear();
    }

    if (mounted) setState(() {});
  }

  // ========== CHART WIDGET ==========
  Widget buildChart() {
    final double minX = (t - maxPoints).clamp(0, double.infinity).toDouble();
    final double maxX = t;

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: -3, // accelerometer đúng khoảng ±2g → thêm margin
          maxY: 3,

          lineBarsData: [
            LineChartBarData(
              spots: xList,
              color: Colors.red,
              isCurved: true,
              barWidth: 2,
              dotData: FlDotData(show: false),
            ),
            LineChartBarData(
              spots: yList,
              color: Colors.green,
              isCurved: true,
              barWidth: 2,
              dotData: FlDotData(show: false),
            ),
            LineChartBarData(
              spots: zList,
              color: Colors.blue,
              isCurved: true,
              barWidth: 2,
              dotData: FlDotData(show: false),
            ),
          ],

          gridData: FlGridData(show: true),
          borderData: FlBorderData(show: true),
        ),
      ),
    );
  }

  // ========== UI ==========
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
          const SizedBox(height: 12),
          Text("📥 Received: $receivedSamples samples",
              style: const TextStyle(fontSize: 16)),
          Text("📤 Sent: $sentSamples samples",
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue)),
          const SizedBox(height: 10),
          const Text("BLE Accelerometer Streaming...",
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
