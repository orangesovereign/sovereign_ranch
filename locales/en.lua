-- Sovereign Ranch — English locale
-- Every player-facing string lives here. Access via T('key', ...).

Locales = Locales or {}

Locales['en'] = {
  -- generic
  no_permission   = 'You do not have the standing for that.',
  not_a_member    = 'You are not part of this ranch\'s crew.',
  ranch_missing   = 'No ranch record for that property.',

  -- lifecycle
  ranch_activated_title = 'Deed Registered',
  ranch_activated       = '%s is now your ranch. The brand is yours to build.',
  ranch_torndown_title  = 'Ranch Closed',
  ranch_torndown        = 'The ranch at %s is no longer yours. The crew has been released.',

  -- crew
  hired_title     = 'Taken On',
  hired           = 'You have been taken on at %s as %s.',
  fired_title     = 'Let Go',
  fired           = 'You have been let go from %s.',
  promoted_title  = 'New Standing',
  promoted        = 'You now stand as %s at %s.',
  crew_full       = 'The bunkhouse is full — no room for another hand.',
  already_crewed  = 'They already ride for a ranch.',
}
