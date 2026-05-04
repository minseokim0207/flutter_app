import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() => runApp(const MaterialApp(home: MapViewer()));

// 좌표와 장소 이름을 함께 저장하기 위한 전용 클래스를 하나 만듭니다.
class MapMarker {
  final Offset position;
  final String name;

  MapMarker({required this.position, required this.name});
}

class MapViewer extends StatefulWidget {
  const MapViewer({super.key});

  @override
  State<MapViewer> createState() => _MapViewerState();
}

class _MapViewerState extends State<MapViewer> {
  // 이제 Offset(좌표) 대신 MapMarker(좌표+이름) 객체들을 저장합니다.
  List<MapMarker> _markers = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MAP VIEWER')),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                children: [
                  GestureDetector(
                    onTapDown: (TapDownDetails details) {
                      double pixelX = details.localPosition.dx;
                      double pixelY = details.localPosition.dy;
                      
                      // 클릭 시 팝업을 먼저 띄웁니다.
                      showDialog(
                        context: context,
                        builder: (context) {
                          String placeName = "";
                          return AlertDialog(
                            title: const Text('장소 저장'),
                            content: TextField(
                              onChanged: (value) => placeName = value,
                              decoration: const InputDecoration(hintText: "예: 화장실, 안내데스크"),
                            ),
                            actions: [
                              TextButton(
                                child: const Text('취소'),
                                onPressed: () {
                                  Navigator.pop(context);
                                },
                              ),
                              TextButton(
                                child: const Text('저장'),
                                onPressed: () {
                                  Navigator.pop(context);
                                  
                                  // '저장'을 눌렀을 때만 리스트에 마커(좌표+이름)를 추가하고 화면을 갱신합니다.
                                  setState(() {
                                    _markers.add(MapMarker(
                                      position: Offset(pixelX, pixelY),
                                      name: placeName,
                                    ));
                                  });
                                  
                                  // ROS2로 데이터 전송
                                  sendToRos(placeName, pixelX, pixelY); 
                                },
                              ),
                            ],
                          );
                        },
                      );
                    },
                    child: Image.network(
                      'http://127.0.0.1:8080/map_img/auto_map.png',
                      width: 640,
                      height: 640,
                      fit: BoxFit.fill,
                      errorBuilder: (context, error, stackTrace) => 
                        const Text('이미지를 불러올 수 없습니다. 서버를 확인하세요.'),
                    ),
                  ),
                  
                  // 저장된 마커 리스트를 화면에 그려줍니다.
                  ..._markers.map((marker) {
                    return Positioned(
                      // 아이콘과 텍스트의 중앙 정렬을 위해 위치를 살짝 왼쪽 위로 보정합니다.
                      left: marker.position.dx - 30, 
                      top: marker.position.dy - 24,  
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.location_on, 
                            color: Colors.red,
                            size: 24,
                          ),
                          // 마커 아래에 뜨는 이름 텍스트 설정
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.8), // 지도 위에서 글씨가 잘 보이게 반투명 배경 추가
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              marker.name,
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(), // 끝부분 수정됨 (.toList() 사용)
                ],
              ),
              const SizedBox(height: 20),
              const Text('지도에서 위치를 터치해 장소를 저장하세요!'),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _markers.clear();
                  });
                },
                child: const Text('장소 지우기'),
              )
            ],
          ),
        ),
      ),
    );
  }
}

void sendToRos(String name, double px, double py) {
  double resolution = 0.05; 
  double originX = -10;
  double originY = -10;
  double imageHeight = 640; 

  double realX = (px * resolution) + originX;
  double realY = ((imageHeight - py) * resolution) + originY;

  Map<String, dynamic> locationData = {
    "name": name,
    "x": realX,
    "y": realY
  };

  // 1. ROS2 Rosbridge 서버와 WebSocket으로 연결합니다. (기본 포트 9090)
  final channel = WebSocketChannel.connect(Uri.parse('ws://127.0.0.1:9090'));

  // 2. Rosbridge 규격에 맞게 메시지를 포장합니다.
  var rosMessage = {
    "op": "publish",
    "topic": "/save_location",
    "msg": {
      "data": jsonEncode(locationData)
    }
  };

  // 3. 데이터를 전송합니다.
  channel.sink.add(jsonEncode(rosMessage));
  
  print("ROS2로 전송 완료: $name");

  // 4. 전송 후 채널을 닫아줍니다. (단발성 전송용)
  Future.delayed(const Duration(seconds: 1), () {
    channel.sink.close();
  });
}