import QtQuick
import QtQuick.Particles
import QtQuick.Shapes

// Weather atmosphere drawn between the blurred wallpaper and the clock.
// Cloudy and night are pure color grading (applied to the wallpaper in
// LockView); here sunny days add a faint glow and motes, rain/storm/snow
// add falling particles, storm adds lightning, snowstorm frosty edges.
Item {
  id: backdrop

  property string kind: ""            // sunny | cloudy | rain | storm | snow | snowstorm
  property bool night: false
  property real intensity: 1.0

  readonly property bool rainy: kind === "rain" || kind === "storm"
  readonly property bool snowy: kind === "snow" || kind === "snowstorm"
  readonly property real k: Math.max(0.1, intensity)

  function asset(name) { return Qt.resolvedUrl("assets/" + name) }

  enabled: false
  // Hidden (and particles paused) when there's no weather effect.
  visible: kind !== ""

  // (Weather/night color grading is applied to the wallpaper in LockView.)

  // ---- Sun glow from the top-right, slowly breathing (day only).
  Shape {
    id: glow
    anchors.fill: parent
    visible: backdrop.kind === "sunny" && !backdrop.night   // clear nights are just color grading
    preferredRendererType: Shape.CurveRenderer
    opacity: 0.0

    SequentialAnimation on opacity {
      running: glow.visible
      loops: Animation.Infinite
      NumberAnimation { to: backdrop.night ? 0.22 : 0.40; duration: 6000; easing.type: Easing.InOutSine }
      NumberAnimation { to: backdrop.night ? 0.12 : 0.22; duration: 6000; easing.type: Easing.InOutSine }
    }

    ShapePath {
      strokeWidth: -1
      fillGradient: RadialGradient {
        centerX: glow.width * 0.88; centerY: -glow.height * 0.08
        centerRadius: glow.height * (backdrop.night ? 0.55 : 0.95)
        focalX: centerX; focalY: centerY
        GradientStop { position: 0.0; color: backdrop.night ? "#c8d4ff" : "#ffd98a" }
        GradientStop { position: 0.45; color: backdrop.night ? "#406080b0" : "#55ffc870" }
        GradientStop { position: 1.0; color: "transparent" }
      }
      startX: 0; startY: 0
      PathLine { x: glow.width; y: 0 }
      PathLine { x: glow.width; y: glow.height }
      PathLine { x: 0; y: glow.height }
      PathLine { x: 0; y: 0 }
    }
  }

  // ---- Snowstorm frost creeping in from the edges.
  Shape {
    id: frost
    anchors.fill: parent
    visible: backdrop.kind === "snowstorm"
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeWidth: -1
      fillGradient: RadialGradient {
        centerX: frost.width / 2; centerY: frost.height / 2
        centerRadius: Math.sqrt(frost.width * frost.width + frost.height * frost.height) / 2
        focalX: centerX; focalY: centerY
        GradientStop { position: 0.6; color: "transparent" }
        GradientStop { position: 1.0; color: backdrop.night ? "#40b8c8e0" : "#55eef4ff" }
      }
      startX: 0; startY: 0
      PathLine { x: frost.width; y: 0 }
      PathLine { x: frost.width; y: frost.height }
      PathLine { x: 0; y: frost.height }
      PathLine { x: 0; y: 0 }
    }
  }

  // ---- Particles
  // ImageParticle blends premultiplied and ignores `alpha` (and a color's
  // alpha) for the RGB part, so translucent particles just add light. Give
  // it the color with the transparency already multiplied in instead.
  function tint(c, a) {
    var col = Qt.lighter(c, 1.0)
    return Qt.rgba(col.r * a, col.g * a, col.b * a, a)
  }

  ParticleSystem {
    id: sys
    anchors.fill: parent
    // Only tick when some emitter can be active; an idle running system still
    // forces a redraw every frame.
    running: backdrop.visible && (backdrop.rainy || backdrop.snowy || (backdrop.kind === "sunny" && !backdrop.night))
  }

  // Drop the previous weather's particles and
  // restart looping animations: their targets are read once at start, so a
  // loop started for rain would keep rain's values after switching to storm.
  onKindChanged: {
    sys.reset()
    windGusts.restart()
    surgeGusts.restart()
  }

  // Sunny days: a few warm motes floating up.
  ImageParticle {
    system: sys
    groups: ["mote"]
    source: backdrop.asset("soft-dot.png")
    color: backdrop.tint("#ffe2a0", 0.16)
    entryEffect: ImageParticle.Fade
    rotationVariation: 180
  }
  Emitter {
    system: sys
    group: "mote"
    enabled: backdrop.kind === "sunny" && !backdrop.night
    width: backdrop.width; height: backdrop.height
    emitRate: 1.2 * backdrop.k
    lifeSpan: 10000; lifeSpanVariation: 3000
    startTime: 10000
    size: 22; sizeVariation: 12
    velocity: PointDirection { y: -7; yVariation: 4; xVariation: 6 }
  }

  // Rain in three depth layers (far: short, faint, many; near: long, soft,
  // fast, few), all bent by a slowly gusting wind. Angles are degrees from
  // the +x axis, so 90 is straight down; nearer layers slant a bit more.
  readonly property bool storm: kind === "storm"
  property real wind: storm ? 24 : 4
  SequentialAnimation on wind {
    id: windGusts
    running: backdrop.rainy && backdrop.visible
    loops: Animation.Infinite
    NumberAnimation { to: backdrop.storm ? 34 : 7; duration: backdrop.storm ? 2500 : 4000; easing.type: Easing.InOutSine }
    NumberAnimation { to: backdrop.storm ? 18 : 1; duration: backdrop.storm ? 3500 : 6000; easing.type: Easing.InOutSine }
    NumberAnimation { to: backdrop.storm ? 28 : 5; duration: backdrop.storm ? 3000 : 5000; easing.type: Easing.InOutSine }
  }
  // Storm gusts: rain thickens into sheets and eases off again.
  property real surge: 1.0
  SequentialAnimation on surge {
    id: surgeGusts
    running: backdrop.storm && backdrop.visible
    loops: Animation.Infinite
    NumberAnimation { to: 1.6; duration: 1800; easing.type: Easing.InOutSine }
    NumberAnimation { to: 0.8; duration: 3200; easing.type: Easing.InOutSine }
    NumberAnimation { to: 1.3; duration: 2400; easing.type: Easing.InOutSine }
    NumberAnimation { to: 1.0; duration: 2600; easing.type: Easing.InOutSine }
  }
  readonly property real rainRate: (storm ? 4.0 * surge : 1.0) * k
  readonly property real rainSpeed: storm ? 1.35 : 1.0
  readonly property real rainDim: night ? 0.7 : 1.0

  ImageParticle {
    system: sys
    groups: ["rainFar"]
    source: backdrop.asset("rain-streak.png")
    color: backdrop.tint("#dde6f0", 0.18 * backdrop.rainDim)
    autoRotation: true
  }
  Emitter {
    system: sys
    group: "rainFar"
    enabled: backdrop.rainy
    x: -backdrop.width * 0.1; y: -40
    width: backdrop.width * 1.7; height: 1
    emitRate: 160 * backdrop.rainRate
    lifeSpan: 2200
    size: backdrop.storm ? 28 : 20; sizeVariation: 8
    velocity: AngleDirection { angle: 90 + backdrop.wind * 0.8; angleVariation: 4; magnitude: 650 * backdrop.rainSpeed; magnitudeVariation: 120 }
  }

  ImageParticle {
    system: sys
    groups: ["rainMid"]
    source: backdrop.asset("rain-streak.png")
    color: backdrop.tint("#ffffff", 0.30 * backdrop.rainDim)
    autoRotation: true
  }
  Emitter {
    system: sys
    group: "rainMid"
    enabled: backdrop.rainy
    x: -backdrop.width * 0.1; y: -80
    width: backdrop.width * 1.7; height: 1
    emitRate: 80 * backdrop.rainRate
    lifeSpan: 1400
    size: backdrop.storm ? 64 : 44; sizeVariation: 14
    velocity: AngleDirection { angle: 90 + backdrop.wind; angleVariation: 3; magnitude: 1100 * backdrop.rainSpeed; magnitudeVariation: 200 }
  }

  ImageParticle {
    system: sys
    groups: ["rainNear"]
    source: backdrop.asset("rain-streak-soft.png")
    color: backdrop.tint("#ffffff", 0.22 * backdrop.rainDim)
    autoRotation: true
  }
  Emitter {
    system: sys
    group: "rainNear"
    enabled: backdrop.rainy
    x: -backdrop.width * 0.1; y: -200
    width: backdrop.width * 1.7; height: 1
    emitRate: 9 * backdrop.rainRate
    lifeSpan: 900
    size: backdrop.storm ? 200 : 150; sizeVariation: 50
    velocity: AngleDirection { angle: 90 + backdrop.wind * 1.3; angleVariation: 2; magnitude: 2000 * backdrop.rainSpeed; magnitudeVariation: 300 }
  }

  // Snow: soft flakes that wobble; a snowstorm is dense and wind-driven.
  ImageParticle {
    system: sys
    groups: ["snow"]
    source: backdrop.asset("soft-dot.png")
    color: backdrop.tint("#ffffff", backdrop.night ? 0.6 : 0.85)
  }
  Emitter {
    system: sys
    group: "snow"
    enabled: backdrop.snowy
    x: backdrop.kind === "snowstorm" ? -backdrop.width * 0.8 : -40
    y: -40
    width: backdrop.kind === "snowstorm" ? backdrop.width * 1.8 : backdrop.width + 80
    height: 1
    emitRate: (backdrop.kind === "snowstorm" ? 260 : 55) * backdrop.k
    lifeSpan: backdrop.kind === "snowstorm" ? 4500 : 11000
    startTime: lifeSpan
    size: 7; sizeVariation: 4
    velocity: AngleDirection {
      angle: backdrop.kind === "snowstorm" ? 55 : 90
      angleVariation: backdrop.kind === "snowstorm" ? 10 : 18
      magnitude: backdrop.kind === "snowstorm" ? 480 : 85
      magnitudeVariation: backdrop.kind === "snowstorm" ? 160 : 35
    }
  }
  Wander {
    system: sys
    groups: ["snow"]
    xVariance: 60
    pace: 60
  }

  // ---- Lightning: a double flash every few seconds in a storm.
  Rectangle {
    id: flash
    anchors.fill: parent
    color: "#eef3ff"
    opacity: 0
  }

  SequentialAnimation {
    id: lightning
    NumberAnimation { target: flash; property: "opacity"; to: 0.38; duration: 60 }
    NumberAnimation { target: flash; property: "opacity"; to: 0.05; duration: 90 }
    NumberAnimation { target: flash; property: "opacity"; to: 0.25; duration: 50 }
    NumberAnimation { target: flash; property: "opacity"; to: 0; duration: 700; easing.type: Easing.OutQuad }
  }

  Timer {
    running: backdrop.kind === "storm" && backdrop.visible
    repeat: true
    interval: 7000
    onTriggered: {
      interval = 5000 + Math.random() * 10000
      lightning.restart()
    }
  }
}
