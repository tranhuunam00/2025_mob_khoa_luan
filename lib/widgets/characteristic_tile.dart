import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import "../utils/snackbar.dart";
import "descriptor_tile.dart";
import 'package:http/http.dart' as http;

import './chart_screen.dart'; // ⬅ nhớ import thêm màn hình chart

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> sendDataToAPI(List<Map<String, dynamic>> values) async {
  final url = Uri.parse("http://222.255.214.218:3001/iot");
  final body = jsonEncode({"data": values});

  try {
    final response = await http.post(url,
        headers: {"Content-Type": "application/json"}, body: body);

    if (response.statusCode == 200 || response.statusCode == 201) {
      print("Dữ liệu đã gửi thành công");
    } else {
      print("Lỗi server: ${response.statusCode}");
    }
  } catch (e) {
    print("Lỗi kết nối API: $e");
  }
}

String processDataAccelerometer(List<int> data) {
  List<double> result = [];

  for (int i = 0; i + 2 < data.length; i += 3) {
    int sign = data[i] == 1 ? 1 : -1;
    int intPart = data[i + 1];
    int decPart = data[i + 2];
    result.add(sign * (intPart + decPart / 100.0));
  }

  return result.map((e) => e.toString()).join(", ");
}

class CharacteristicTile extends StatefulWidget {
  final BluetoothCharacteristic characteristic;
  final List<DescriptorTile> descriptorTiles;

  const CharacteristicTile({
    Key? key,
    required this.characteristic,
    required this.descriptorTiles,
  }) : super(key: key);

  @override
  State<CharacteristicTile> createState() => _CharacteristicTileState();
}

class _CharacteristicTileState extends State<CharacteristicTile> {
  BluetoothCharacteristic get c => widget.characteristic;

  List<int> _value = [];
  List<Map<String, dynamic>> _values = [];
  int selectedUserId = 1;
  late StreamSubscription<List<int>> _lastValueSubscription;

  @override
  void initState() {
    super.initState();

    /// ❗ Nếu là UUID chính → KHÔNG xử lý ở đây
    if (_isAccelUUID()) return;

    _lastValueSubscription =
        widget.characteristic.lastValueStream.listen((value) {
      handleNewValue(value);
    });
  }

  bool _isAccelUUID() {
    return widget.characteristic.uuid.str.toLowerCase() ==
        "19b10001-e8f2-537e-4f6c-d104768a1214";
  }

  @override
  void dispose() {
    if (!_isAccelUUID()) {
      _lastValueSubscription.cancel();
    }
    super.dispose();
  }

  // Xử lý bình thường cho các characteristic khác
  Future<void> handleNewValue(List<int> value) async {
    _value = value;

    String formatted = processDataAccelerometer(value);

    if (formatted.isNotEmpty) {
      _values.add({
        "createdAt": DateTime.now().toIso8601String(),
        "value": formatted,
        "user": selectedUserId
      });
    }

    if (_values.length >= 500) {
      await sendDataToAPI(_values);
      _values.clear();
      await c.setNotifyValue(false);
    }

    if (mounted) setState(() {});
  }

  // ========================= UI =========================

  @override
  Widget build(BuildContext context) {
    final uuid = c.uuid.str.toLowerCase();
    print("USER ID: ${selectedUserId}");

    /// 🔥 Nếu là characteristic chính → chuyển sang ChartScreen
    if (_isAccelUUID()) {
      return ListTile(
        title: const Text(
          "Accelerometer Stream",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text("UUID: $uuid"),
        trailing: const Icon(Icons.bar_chart, color: Colors.blue),
        onTap: () async {
          int? userId = await _showUserDialog(context);

          if (userId != null) {
            selectedUserId = userId;

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChartScreen(
                  characteristic: c,
                  userId: selectedUserId,
                ),
              ),
            );
          }
        },
      );
    }

    /// 🔥 Các characteristic khác → giữ nguyên UI cũ
    return ExpansionTile(
      title: ListTile(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Characteristic'),
            Text('0x${c.uuid.str.toUpperCase()}'),
            Text(
              _value.toString(),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        subtitle: buildButtonRow(context),
        contentPadding: EdgeInsets.zero,
      ),
      children: widget.descriptorTiles,
    );
  }

  Widget buildButtonRow(BuildContext context) {
    return Row(
      children: [
        if (c.properties.read)
          TextButton(
            child: const Text("Read"),
            onPressed: () async {
              await c.read();
              setState(() {});
            },
          ),
        if (c.properties.write)
          TextButton(
            child: const Text("Write"),
            onPressed: () async => await c.write([1, 2, 3, 4]),
          ),
        if (c.properties.notify)
          TextButton(
            child: Text(c.isNotifying ? "Unsubscribe" : "Subscribe"),
            onPressed: () async {
              await c.setNotifyValue(!c.isNotifying);
              setState(() {});
            },
          ),
      ],
    );
  }
}

Future<int?> _showUserDialog(BuildContext context) async {
  TextEditingController controller = TextEditingController();

  return showDialog<int>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text("Nhập User ID"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: "Ví dụ: 1",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text("Hủy"),
          ),
          TextButton(
            onPressed: () {
              int? userId = int.tryParse(controller.text);

              if (userId == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("User ID không hợp lệ")),
                );
                return;
              }

              Navigator.pop(context, userId);
            },
            child: const Text("OK"),
          ),
        ],
      );
    },
  );
}
