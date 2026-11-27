/// Compile-time isolation switch for the experimental ShamFlix build.
/// When enabled, every Supabase operation is redirected to localhost and cannot
/// reach the production project.
const bool kShamFlixTrialMode = bool.fromEnvironment(
  'SHAMFLIX_TRIAL_MODE',
  defaultValue: false,
);
