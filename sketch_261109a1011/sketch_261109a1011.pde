
import netP5.*;
import oscP5.*;

import processing.video.*;
import processing.serial.*;

Capture cam;
Serial arduino;


// ========================================
// WEKINATOR OSC
// ========================================

OscP5 oscP5;
NetAddress wekinator;

final int WEKINATOR_INPUT_PORT = 6448;
final int PROCESSING_OUTPUT_PORT = 12000;


// ========================================
// CAMERA FEATURE DATA
// ========================================

PImage previousFrame;
boolean hasPreviousFrame = false;

int changedPixels = 0;
float smoothedMotion = 0;

final float DETECTION_THRESHOLD = 50;
final float SMOOTHING_FACTOR = 0.15;


// ========================================
// ARDUINO COMMUNICATION
// ========================================

boolean arduinoReady = false;
boolean busy = false;

int lastHandshakeTime = 0;

String currentCommand = "READY";
String motorStatus = "CONNECTING";


// ========================================
// WEKINATOR CLASSIFICATION
// ========================================

int wekinatorClass = 0;

float rawWekinatorOutput = 0;

String motionMode = "WAITING";

// Prevent repeated STOP commands
boolean stopCommandSent = false;


// ========================================
// SETUP
// ========================================

void setup() {

  size(1000, 580);

  textFont(createFont("Arial", 18));


  // ======================================
  // OSC CONNECTION
  // ======================================

  oscP5 = new OscP5(this, PROCESSING_OUTPUT_PORT);

  wekinator = new NetAddress(
    "127.0.0.1",
    WEKINATOR_INPUT_PORT
  );

  println("================================");
  println("WEKINATOR CONNECTION");
  println("Input Port: 6448");
  println("Output Port: 12000");
  println("================================");


  // ======================================
  // CAMERA
  // ======================================

  String[] cameras = Capture.list();

  if (cameras.length > 0) {

    cam = new Capture(
      this,
      640,
      480,
      cameras[0]
    );

    cam.start();

    println("Camera connected: " + cameras[0]);

  } else {

    println("No camera found.");
  }


  // ======================================
  // ARDUINO SERIAL
  // ======================================

  String[] ports = Serial.list();

  println("Available serial ports:");

  for (int i = 0; i < ports.length; i++) {

    println(i + ": " + ports[i]);
  }

  String selectedPort = "";

  for (int i = 0; i < ports.length; i++) {

    if (ports[i].contains("usbmodem")) {

      selectedPort = ports[i];
      break;
    }
  }

  if (selectedPort.equals("") && ports.length > 0) {

    selectedPort = ports[0];
  }

  if (!selectedPort.equals("")) {

    arduino = new Serial(
      this,
      selectedPort,
      9600
    );

    arduino.bufferUntil('\n');

    println("Connected to Arduino: " + selectedPort);

    motorStatus = "WAITING FOR ARDUINO";

    lastHandshakeTime = millis();

  } else {

    motorStatus = "NO SERIAL PORT";
  }
}


// ========================================
// DRAW
// ========================================

void draw() {

  background(245);


  // ======================================
  // CAMERA UPDATE
  // ======================================

  if (cam != null && cam.available()) {

    cam.read();

    detectMotion();

    if (hasPreviousFrame) {

      sendToWekinator();
    }
  }


  // ======================================
  // ARDUINO HANDSHAKE
  // ======================================

  if (arduino != null && !arduinoReady) {

    if (millis() - lastHandshakeTime > 1000) {

      arduino.write("?\n");

      lastHandshakeTime = millis();
    }
  }


  // ======================================
  // WEKINATOR COMMAND CONTROL
  // ======================================

  if (arduinoReady && !busy) {


    // CLASS 1 = STOP
    if (wekinatorClass == 1) {

      if (!stopCommandSent) {

        sendMotorCommand('1', "STOP");
      }
    }


    // CLASS 2 = MID
    else if (wekinatorClass == 2) {

      stopCommandSent = false;

      sendMotorCommand('2', "MID");
    }


    // CLASS 3 = FAST
    else if (wekinatorClass == 3) {

      stopCommandSent = false;

      sendMotorCommand('3', "FAST");
    }
  }


  // ======================================
  // DISPLAY
  // ======================================

  drawCamera();

  drawControlPanel();
}


// ========================================
// CAMERA FEATURE EXTRACTION
// ========================================

void detectMotion() {

  cam.loadPixels();

  if (!hasPreviousFrame) {

    previousFrame = createImage(
      cam.width,
      cam.height,
      RGB
    );

    previousFrame.loadPixels();

    arrayCopy(
      cam.pixels,
      previousFrame.pixels
    );

    previousFrame.updatePixels();

    hasPreviousFrame = true;

    return;
  }

  previousFrame.loadPixels();

  int count = 0;

  int sampleStep = 4;

  for (int y = 0; y < cam.height; y += sampleStep) {

    for (int x = 0; x < cam.width; x += sampleStep) {

      int index = y * cam.width + x;

      color current = cam.pixels[index];

      color previous = previousFrame.pixels[index];

      float currentGray =
        red(current) * 0.299 +
        green(current) * 0.587 +
        blue(current) * 0.114;

      float previousGray =
        red(previous) * 0.299 +
        green(previous) * 0.587 +
        blue(previous) * 0.114;

      float difference = abs(
        currentGray - previousGray
      );

      if (difference > DETECTION_THRESHOLD) {

        count++;
      }
    }
  }

  changedPixels = count;

  smoothedMotion = lerp(
    smoothedMotion,
    changedPixels,
    SMOOTHING_FACTOR
  );


  // Update previous frame
  arrayCopy(
    cam.pixels,
    previousFrame.pixels
  );

  previousFrame.updatePixels();
}


// ========================================
// SEND CAMERA FEATURES TO WEKINATOR
// ========================================

void sendToWekinator() {

  OscMessage message = new OscMessage("/wek/inputs");

  message.add((float) changedPixels);

  message.add((float) smoothedMotion);

  oscP5.send(message, wekinator);
}


// ========================================
// RECEIVE WEKINATOR CLASSIFICATION
// ========================================

void oscEvent(OscMessage message) {

  if (message.checkAddrPattern("/wek/outputs")) {

    if (message.typetag().length() > 0) {

      float output = message.get(0).floatValue();

      int newClass = round(output);


      // Only accept Wekinator classes 1, 2, 3
      if (newClass >= 1 && newClass <= 3) {

        rawWekinatorOutput = output;

        // Update classification
        if (newClass != wekinatorClass) {

          wekinatorClass = newClass;


          if (newClass == 1) {

            motionMode = "STOP";

            println("==========================");
            println("WEKINATOR: CLASS 1");
            println("MODE: STOP");
            println("==========================");
          }

          else if (newClass == 2) {

            motionMode = "MID";

            println("==========================");
            println("WEKINATOR: CLASS 2");
            println("MODE: MID");
            println("==========================");
          }

          else if (newClass == 3) {

            motionMode = "FAST";

            println("==========================");
            println("WEKINATOR: CLASS 3");
            println("MODE: FAST");
            println("==========================");
          }
        }
      }
    }
  }
}


// ========================================
// SEND MOTOR COMMAND TO ARDUINO
// ========================================

void sendMotorCommand(char command, String label) {

  if (arduino == null) return;

  if (!arduinoReady || busy) return;


  currentCommand = label;

  motorStatus = "RUNNING " + label;

  busy = true;

  arduinoReady = false;


  if (command == '1') {

    stopCommandSent = true;
  }


  // Send exact Wekinator classification
  arduino.write(command);

  arduino.write('\n');


  println("--------------------------------");
  println("WEKINATOR CLASS: " + wekinatorClass);
  println("PROCESSING COMMAND: " + label);
  println("ARDUINO COMMAND: " + command);
  println("--------------------------------");
}


// ========================================
// RECEIVE ARDUINO MESSAGES
// ========================================

void serialEvent(Serial port) {

  String message = port.readStringUntil('\n');

  if (message == null) return;

  message = trim(message);

  println("Arduino: " + message);


  // ======================================
  // MID
  // ======================================

  if (message.equals("RUNNING MID")) {

    motorStatus = "RUNNING MID";

    println("ARDUINO CONFIRMED: MID");
  }


  // ======================================
  // FAST
  // ======================================

  else if (message.equals("RUNNING FAST")) {

    motorStatus = "RUNNING FAST";

    println("ARDUINO CONFIRMED: FAST");
  }


  // ======================================
  // RELEASING
  // ======================================

  else if (message.equals("RELEASING")) {

    motorStatus = "RELEASING";

    println("MOTORS RELEASING FORWARD");
  }


  // ======================================
  // MOVEMENT COMPLETED
  // ======================================

  else if (message.equals("MOVEMENT COMPLETED")) {

    motorStatus = "COMPLETED";

    println("MOVEMENT COMPLETED");
  }


  // ======================================
  // STOP
  // ======================================

  else if (message.equals("STOP")) {

    arduinoReady = true;

    busy = false;

    motorStatus = "READY";

    currentCommand = "STOP";

    println("MOTORS STOPPED");
  }


  // ======================================
  // READY
  // ======================================

  else if (message.equals("READY")) {

    arduinoReady = true;

    busy = false;

    motorStatus = "READY";

    println("ARDUINO READY");
    println("LATEST WEKINATOR CLASS: " + wekinatorClass);
  }
}


// ========================================
// CAMERA DISPLAY
// ========================================

void drawCamera() {

  fill(30);

  textSize(20);

  text("LIVE CAMERA", 20, 30);

  if (cam != null) {

    image(cam, 20, 50, 640, 480);

  } else {

    fill(100);

    rect(20, 50, 640, 480);

    fill(255);

    text("Camera unavailable", 230, 290);
  }
}


// ========================================
// CONTROL PANEL
// ========================================

void drawControlPanel() {

  int x = 690;


  // TITLE
  fill(30);

  textSize(22);

  text("WEKINATOR CONTROL", x, 40);


  // ======================================
  // CLASSIFICATION
  // ======================================

  fill(100);

  textSize(14);

  text("WEKINATOR CLASSIFICATION", x, 120);


  if (wekinatorClass == 2) {

    fill(30, 130, 220);

  }

  else if (wekinatorClass == 3) {

    fill(220, 100, 30);

  }

  else {

    fill(0, 150, 80);
  }

  textSize(48);

  text(motionMode, x, 175);


  // ======================================
  // RAW WEKINATOR OUTPUT
  // ======================================

  fill(100);

  textSize(14);

  text("RAW OUTPUT: " + nf(rawWekinatorOutput, 1, 2), x, 210);


  // ======================================
  // MOTOR STATUS
  // ======================================

  fill(100);

  textSize(14);

  text("MOTOR STATUS", x, 270);

  fill(30);

  textSize(24);

  text(motorStatus, x, 305);


  // ======================================
  // CURRENT COMMAND
  // ======================================

  fill(100);

  textSize(14);

  text("CURRENT COMMAND", x, 365);

  fill(30);

  textSize(22);

  text(currentCommand, x, 400);


  // ======================================
  // LOCK STATUS
  // ======================================

  if (busy || !arduinoReady) {

    fill(200, 50, 50);

    textSize(17);

    text("MOTOR: BUSY / LOCKED", x, 520);

  } else {

    fill(0, 150, 80);

    textSize(17);

    text("MOTOR: READY", x, 520);
  }
}
