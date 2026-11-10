// ========================================
// THREE SYNCHRONISED STEPPER MOTORS
// 28BYJ-48 + 74HC595
// Arduino Nano Every
//
// WHEAT MOVEMENT:
// 1. PULL BACKWARD
// 2. RELEASE FORWARD
// 3. RETURN TO INITIAL POSITION
//
// Processing Commands:
// 1 = STOP
// 2 = MID
// 3 = FAST
// ========================================


// ========================================
// MOTOR PIN SETTINGS
// ========================================

// Motor 1
const int motor1Pins[4] = {8, 9, 10, 11};

// Motor 2
const int motor2Pins[4] = {4, 5, 6, 7};

// 74HC595 - Motor 3
const int DATA_PIN  = 2;
const int LATCH_PIN = 3;
const int CLOCK_PIN = 12;


// ========================================
// MOTOR SETTINGS
// ========================================

// Approximately 1024 half-steps = 90°
// Approximately 2048 half-steps = 180°

const int MOVE_STEPS = 400;

// MID speed
const unsigned long MID_INTERVAL_US = 8000;

// FAST speed
const unsigned long FAST_INTERVAL_US = 3500;


// ========================================
// MOVEMENT DIRECTIONS
// ========================================

// Pull wheat backwards
const int PULL_DIRECTION = -1;

// Release wheat forwards
const int RELEASE_DIRECTION = 1;


// ========================================
// HALF-STEP SEQUENCE
// ========================================

const byte stepSequence[8] = {
  B00000001,
  B00000011,
  B00000010,
  B00000110,
  B00000100,
  B00001100,
  B00001000,
  B00001001
};


// ========================================
// MOTOR VARIABLES
// ========================================

int stepIndex = 0;
int currentStep = 0;

unsigned long stepInterval = MID_INTERVAL_US;
unsigned long lastStepMicros = 0;


// ========================================
// MOTOR STATES
// ========================================

enum MotorState {
  IDLE,
  PULLING_BACK,
  RELEASING_FORWARD
};

MotorState motorState = IDLE;


// ========================================
// WRITE MOTOR 1 AND 2
// ========================================

void writeDirectMotor(const int pins[], byte pattern) {

  for (int i = 0; i < 4; i++) {
    digitalWrite(pins[i], bitRead(pattern, i));
  }
}


// ========================================
// WRITE MOTOR 3 THROUGH 74HC595
// ========================================

void writeMotor3(byte pattern) {

  digitalWrite(LATCH_PIN, LOW);

  shiftOut(
    DATA_PIN,
    CLOCK_PIN,
    MSBFIRST,
    pattern
  );

  digitalWrite(LATCH_PIN, HIGH);
}


// ========================================
// UPDATE ALL THREE MOTORS
// ========================================

void updateAllMotors() {

  byte pattern = stepSequence[stepIndex];

  writeDirectMotor(motor1Pins, pattern);
  writeDirectMotor(motor2Pins, pattern);
  writeMotor3(pattern);
}


// ========================================
// MOVE ALL THREE MOTORS TOGETHER
// ========================================

void moveOneStep(int direction) {

  stepIndex += direction;

  if (stepIndex >= 8) {
    stepIndex = 0;
  }

  if (stepIndex < 0) {
    stepIndex = 7;
  }

  updateAllMotors();
}


// ========================================
// START MOVEMENT
// ========================================

void startMovement(char command) {

  if (motorState != IDLE) return;

  // COMMAND 1 = STOP
  if (command == '1') {

    Serial.println("STOP");
    Serial.println("READY");

    return;
  }

  // COMMAND 2 = MID
  if (command == '2') {

    stepInterval = MID_INTERVAL_US;

    Serial.println("RUNNING MID");
  }

  // COMMAND 3 = FAST
  else if (command == '3') {

    stepInterval = FAST_INTERVAL_US;

    Serial.println("RUNNING FAST");
  }

  else {
    return;
  }

  currentStep = 0;

  motorState = PULLING_BACK;

  lastStepMicros = micros();
}


// ========================================
// UPDATE MOTOR MOVEMENT
// ========================================

void updateMotorMovement() {

  unsigned long currentMicros = micros();


  // ======================================
  // PHASE 1: PULL WHEAT BACKWARD
  // ======================================

  if (motorState == PULLING_BACK) {

    if (
      (unsigned long)(currentMicros - lastStepMicros)
      >= stepInterval
    ) {

      lastStepMicros = currentMicros;

      // Pull backwards
      moveOneStep(PULL_DIRECTION);

      currentStep++;

      if (currentStep >= MOVE_STEPS) {

        // Immediately reverse direction
        currentStep = 0;

        motorState = RELEASING_FORWARD;

        lastStepMicros = micros();

        Serial.println("RELEASING");
      }
    }
  }


  // ======================================
  // PHASE 2: RELEASE WHEAT FORWARD
  // ======================================

  else if (motorState == RELEASING_FORWARD) {

    if (
      (unsigned long)(currentMicros - lastStepMicros)
      >= stepInterval
    ) {

      lastStepMicros = currentMicros;

      // Release forwards
      moveOneStep(RELEASE_DIRECTION);

      currentStep++;

      if (currentStep >= MOVE_STEPS) {

        currentStep = 0;

        motorState = IDLE;

        // Return to initial position
        Serial.println("MOVEMENT COMPLETED");
        Serial.println("READY");
      }
    }
  }
}


// ========================================
// SERIAL COMMUNICATION
// ========================================

void receiveSerialCommand() {

  while (Serial.available() > 0) {

    char command = Serial.read();

    if (command == '\n' || command == '\r') {
      continue;
    }

    // HANDSHAKE
    if (command == '?') {

      if (motorState == IDLE) {
        Serial.println("READY");
      }

      continue;
    }

    // ACCEPT COMMANDS ONLY WHEN IDLE
    if (motorState == IDLE) {

      if (
        command == '1' ||
        command == '2' ||
        command == '3'
      ) {

        startMovement(command);
      }
    }
  }
}


// ========================================
// SETUP
// ========================================

void setup() {

  Serial.begin(9600);

  // Motor 1 and Motor 2 pins
  for (int i = 0; i < 4; i++) {

    pinMode(motor1Pins[i], OUTPUT);
    pinMode(motor2Pins[i], OUTPUT);
  }

  // 74HC595 pins
  pinMode(DATA_PIN, OUTPUT);
  pinMode(LATCH_PIN, OUTPUT);
  pinMode(CLOCK_PIN, OUTPUT);

  digitalWrite(LATCH_PIN, HIGH);

  // Initialise motors
  updateAllMotors();

  motorState = IDLE;

  Serial.println("READY");
  Serial.println("THREE MOTORS READY");
}


// ========================================
// MAIN LOOP
// ========================================

void loop() {

  receiveSerialCommand();

  updateMotorMovement();

}
