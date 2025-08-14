import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:isolate';

class User {
  final UserData data;
  final Support support;

  User({required this.data, required this.support});

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      data: UserData.fromJson(json['data']),
      support: Support.fromJson(json['support']),
    );
  }

  Map<String, dynamic> toJson() {
    return {'data': data.toJson(), 'support': support.toJson()};
  }

  @override
  String toString() {
    return JsonEncoder.withIndent('  ').convert(this);
  }
}

class UserData {
  final int id;
  final String email;
  final String firstName;
  final String lastName;
  final String avatar;

  UserData({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.avatar,
  });

  factory UserData.fromJson(Map<String, dynamic> json) {
    return UserData(
      id: json['id'],
      email: json['email'],
      firstName: json['first_name'],
      lastName: json['last_name'],
      avatar: json['avatar'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'first_name': firstName,
      'last_name': lastName,
      'avatar': avatar,
    };
  }
}

class Support {
  final String url;
  final String text;

  Support({required this.url, required this.text});

  factory Support.fromJson(Map<String, dynamic> json) {
    return Support(url: json['url'], text: json['text']);
  }

  Map<String, dynamic> toJson() {
    return {'url': url, 'text': text};
  }
}

Future<User?> fetchUser(int id) async {
  if (id > 20) {
    return null;
  }
  // Генератор случайных чисел
  final random = Random();

  // Списки с данными для генерации
  final firstNames = ['John', 'Jane', 'Alex', 'Emily', 'Chris'];
  final lastNames = ['Doe', 'Smith', 'Johnson', 'Williams', 'Brown'];
  final avatars = [
    'https://ex.in/img/faces/1-image.jpg',
    'https:// ex.in/img/faces/2-image.jpg',
    'https:// ex.in/img/faces/3-image.jpg',
    'https:// ex.in/img/faces/4-image.jpg',
    'https:// ex.in/img/faces/5-image.jpg',
  ];
  final supportUrls = [
    'https:// ex.in/#support-heading',
    'https://example.com/support',
  ];
  final supportTexts = [
    'To keep ReqRes free, contributions are appreciated!',
    'Example support text.',
  ];

  // Имитация задержки, чтобы симулировать сетевой запрос
  await Future.delayed(Duration(milliseconds: 500));

  // Генерация случайных данных
  final firstName = firstNames[random.nextInt(firstNames.length)];
  final lastName = lastNames[random.nextInt(lastNames.length)];
  final email =
      '${firstName.toLowerCase()}.${lastName.toLowerCase()}'
      '@example.com';
  final avatar = avatars[random.nextInt(avatars.length)];
  final supportUrl = supportUrls[random.nextInt(supportUrls.length)];
  final supportText = supportTexts[random.nextInt(supportTexts.length)];

  // Создание объекта User с сгенерированными данными
  final user = User(
    data: UserData(
      id: id,
      email: email,
      firstName: firstName,
      lastName: lastName,
      avatar: avatar,
    ),
    support: Support(url: supportUrl, text: supportText),
  );

  return user;
}

Future<User?> fetchUserWithoutId() async {
  return await fetchUser(1);
}

/// сообщения между главным и создаваемым изолятом
sealed class Message {}

class StartMessage extends Message {
  final SendPort sender;
  final Capability processCapability;
  StartMessage(this.sender, this.processCapability);
}

class StartMessageResponse extends Message {
  final SendPort sender;
  StartMessageResponse(this.sender);
}

class StopMessage extends Message {
  final Capability? processCapability;
  StopMessage([this.processCapability]);
}

class UserRequestMessage extends Message {
  final int id;
  final Capability? processCapability;
  UserRequestMessage(this.id, {this.processCapability});
}

class UserResponseMessage extends Message {
  final User? user;
  UserResponseMessage(this.user);
}

void isolateFetchUser(StartMessage message) async {
  var receivePort = ReceivePort();
  final processCapability = message.processCapability;
  var sendPort = message.sender;
  sendPort.send(StartMessageResponse(receivePort.sendPort));

  receivePort.listen((message) async {
    switch (message) {
      case StopMessage(processCapability: var capability):
        if (capability == processCapability) {
          print('[Isolate] Exit: Permission granted');
          sendPort.send(StopMessage());
          receivePort.close();
          Isolate.current.kill();
        } else {
          print('[Isolate] Exit: Permission denied');
        }
      case UserRequestMessage(id: var id, processCapability: var capability):
        if ((capability == null || capability == processCapability) &&
            id <= 10) {
          print('[Isolate] UserRequest: id <= 10');
          var user = await fetchUser(id);
          sendPort.send(UserResponseMessage(user));
        }
        // Если id больше 10 и заданы права доступа
        // то запрос будет обработан
        else if (capability == processCapability && id > 10) {
          print('[Isolate] UserRequest: Permission granted');
          var user = await fetchUser(id);
          sendPort.send(UserResponseMessage(user));
        } else {
          sendPort.send(UserResponseMessage(null));
        }
    }
  });
}

void main() async {
  final processCapability = Capability();
  var receivePort = ReceivePort();
  await Isolate.spawn(
    isolateFetchUser,
    StartMessage(receivePort.sendPort, processCapability),
  );

  SendPort? sendPort;
  // слушаем порт изолята
  receivePort.listen((message) {
    switch (message) {
      case StartMessageResponse(sender: var port):
        sendPort = port;
      case StopMessage():
        print('Isolate stopped');
        receivePort.close();
      case UserResponseMessage(user: var user):
        print(user);
    }
  });

  await Future.delayed(Duration(seconds: 1));

  while (true) {
    if (sendPort == null) {
      print('Isolate not started');
      break;
    }
    print('Enter user id');
    var input = stdin.readLineSync()!;
    var id = int.tryParse(input);
    if (id is int) {
      print('Add capability? (y/n)');
      var capabilityInput = stdin.readLineSync()!;
      if (capabilityInput.toLowerCase() == 'y') {
        sendPort?.send(
          UserRequestMessage(id, processCapability: processCapability),
        );
      } else {
        sendPort?.send(UserRequestMessage(id));
      }
    } else if (input == 'Exit') {
      sendPort?.send(StopMessage());
    } else if (input == 'exit') {
      sendPort?.send(StopMessage(processCapability));
      break;
    } else {
      print('Invalid user id');
    }
    await Future.delayed(Duration(seconds: 1));
  }
}
