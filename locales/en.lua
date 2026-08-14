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

  -- animals & care (Phase 1)
  animal_fed        = 'Fed.',
  animal_watered    = 'Watered.',
  animal_brushed    = 'Brushed down.',
  animal_treated    = 'The medicine takes. Keep an eye on it.',
  animal_released   = 'Led out to pasture.',
  animal_penned     = 'Sent to the barn.',
  animal_renamed    = 'It answers to %s now.',
  animal_died_title = 'Animal Lost',
  animal_died       = '%s did not make it. See to the rest.',
  care_cooldown     = 'It does not need that yet.',
  trough_filled     = 'The trough is full. They will come to it.',
  trough_watered    = 'Fresh water in the trough.',
  trough_full       = 'That trough is already full.',
  feed_scattered    = 'You scatter the feed across the ground.',
  care_too_far      = 'Get closer to the animal.',
  need_medicine     = 'You need %s for that.',
  not_sick          = 'Nothing ails this animal.',
  herd_full         = 'The %s pen is at capacity.',
  no_hands_present  = 'A hand must be on the property to mind released animals.',
  cannot_afford     = 'The ranch account cannot cover it.',
  bought_title      = 'Stock Purchased',
  bought_drive      = '%d head bought. Drive them home — they will follow you at a walk.',
  bought_delivery   = '%d head bought. Delivery to the ranch in about %d minutes.',
  delivery_title    = 'Delivery Arrived',
  delivery_arrived  = 'Your livestock delivery is in the barn.',
  transit_home      = 'The animals settle onto your land.',
  dealer_no_ranch   = 'Buying stock needs a ranch and the standing to spend its money.',

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
