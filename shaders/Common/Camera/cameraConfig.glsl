// ============================================================
// ETHERREALITY GENESIS™ :: CAMERA CONFIG
//
// Central camera / post-processing configuration.
//
// Current:
//   - camera effect enable states
//   - effect strengths
//
// Future:
//   - additional camera presentation controls
//
// Rendering is intentionally NOT performed here.
// This file only stores shared camera parameters.
// ============================================================


// ============================================================
// CAMERA EFFECT STATES
// ============================================================
//
// These are shader-side defaults.
//
// Iris Shader Pack Settings can later override these values.
// ============================================================

const bool GM_CAMERA_VIGNETTE =
    true;

const bool GM_CAMERA_BLUR =
    true;

const bool GM_CAMERA_ANTIALIASING =
    true;

const bool GM_CAMERA_MOTION_BLUR =
    false;


// ============================================================
// VIGNETTE
// ============================================================
//
// Etherreality Genesis™ uses only a very subtle vignette.
// It should gently focus the image without making the corners
// obviously dark.
// ============================================================

const float GM_VIGNETTE_STRENGTH =
    0.10;

const float GM_VIGNETTE_SOFTNESS =
    0.75;


// ============================================================
// BLUR
// ============================================================
//
// Barely-there blur.
//
// Its purpose is to soften the world very slightly rather than
// visibly blur the image.
// ============================================================

const float GM_BLUR_STRENGTH =
    2.04;


// ============================================================
// ANTI-ALIASING
// ============================================================
//
// Base strength for the future camera AA pass.
//
// The actual AA implementation will be added separately.
// ============================================================

const float GM_AA_STRENGTH =
    1.0;


// ============================================================
// MOTION BLUR
// ============================================================
//
// Disabled by default.
//
// The implementation will later use motion information rather
// than applying a permanent screen blur.
// ============================================================

const float GM_MOTION_BLUR_STRENGTH =
    0.15;

const float GM_MOTION_BLUR_SCALE =
    1.0;


// ============================================================
// CAMERA LIMITS
// ============================================================
//
// Shared safety limits for future post-processing effects.
// ============================================================

const float GM_CAMERA_MIN_VALUE =
    0.0;

const float GM_CAMERA_MAX_VALUE =
    1.0;