extends Node
## FeedbackManager - Tracks aggregate golfer feedback for end-of-day summaries
##
## Listens to golfer_thought signals and maintains counts for daily satisfaction rating.

## Daily feedback counts (reset each day)
var daily_counts: Dictionary = {
	"positive": 0,
	"negative": 0,
	"neutral": 0,
}

## Track specific trigger counts for detailed feedback
var trigger_counts: Dictionary = {}

## Track needs-related complaints separately for actionable insights
var needs_complaints: Dictionary = {
	"tired": 0,
	"hungry": 0,
	"restroom": 0,
	"slow_pace": 0,
	"thirsty": 0,
}

func _ready() -> void:
	EventBus.golfer_thought.connect(_on_golfer_thought)
	EventBus.day_changed.connect(_on_day_changed)
	print("FeedbackManager initialized")

func _on_golfer_thought(_golfer_id: int, trigger_type: int, sentiment: String) -> void:
	# Count by sentiment
	if sentiment in daily_counts:
		daily_counts[sentiment] += 1

	# Count by trigger type
	if trigger_type not in trigger_counts:
		trigger_counts[trigger_type] = 0
	trigger_counts[trigger_type] += 1

	# Track needs-related complaints for actionable feedback
	match trigger_type:
		FeedbackTriggers.TriggerType.TIRED:
			needs_complaints["tired"] += 1
		FeedbackTriggers.TriggerType.HUNGRY:
			needs_complaints["hungry"] += 1
		FeedbackTriggers.TriggerType.NEEDS_RESTROOM:
			needs_complaints["restroom"] += 1
		FeedbackTriggers.TriggerType.SLOW_PACE:
			needs_complaints["slow_pace"] += 1
		FeedbackTriggers.TriggerType.THIRSTY:
			needs_complaints["thirsty"] += 1

func _on_day_changed(_new_day: int) -> void:
	reset_daily_stats()

## Reset stats for new day
func reset_daily_stats() -> void:
	incidents.clear()
	visits.clear()
	returning_today = 0
	service_visits = 0
	service_revenue = 0
	referrals_pending = 0
	referrals_today = 0
	daily_counts = {
		"positive": 0,
		"negative": 0,
		"neutral": 0,
	}
	trigger_counts.clear()
	needs_complaints = {
		"tired": 0,
		"hungry": 0,
		"restroom": 0,
		"slow_pace": 0,
		"thirsty": 0,
	}

## Get overall satisfaction rating (0.0 to 1.0)
## Returns 0.5 if no feedback recorded
func get_satisfaction_rating() -> float:
	var total = daily_counts["positive"] + daily_counts["negative"]
	if total == 0:
		return 0.5  # Neutral if no feedback

	return float(daily_counts["positive"]) / float(total)

## Get total feedback count for the day
func get_total_count() -> int:
	return daily_counts["positive"] + daily_counts["negative"] + daily_counts["neutral"]

## Get the most common complaint (negative trigger)
func get_top_complaint() -> String:
	var worst_trigger: int = -1
	var worst_count: int = 0

	for trigger_type in trigger_counts:
		var sentiment = FeedbackTriggers.get_sentiment(trigger_type)
		if sentiment == "negative" and trigger_counts[trigger_type] > worst_count:
			worst_count = trigger_counts[trigger_type]
			worst_trigger = trigger_type

	if worst_trigger == -1:
		return ""

	# Return a representative message for this trigger
	return FeedbackTriggers.get_random_message(worst_trigger)

## Get the most common compliment (positive trigger)
func get_top_compliment() -> String:
	var best_trigger: int = -1
	var best_count: int = 0

	for trigger_type in trigger_counts:
		var sentiment = FeedbackTriggers.get_sentiment(trigger_type)
		if sentiment == "positive" and trigger_counts[trigger_type] > best_count:
			best_count = trigger_counts[trigger_type]
			best_trigger = trigger_type

	if best_trigger == -1:
		return ""

	return FeedbackTriggers.get_random_message(best_trigger)

## Get summary dictionary for end-of-day panel
func get_daily_summary() -> Dictionary:
	return {
		"satisfaction": get_satisfaction_rating(),
		"positive_count": daily_counts["positive"],
		"negative_count": daily_counts["negative"],
		"neutral_count": daily_counts["neutral"],
		"total_count": get_total_count(),
		"top_complaint": get_top_complaint(),
		"top_compliment": get_top_compliment(),
		"needs_complaints": needs_complaints.duplicate(),
	}

## Get the top unmet need (most complained about)
## Returns empty string if no needs complaints
func get_top_unmet_need() -> String:
	var worst_need: String = ""
	var worst_count: int = 0
	for need_name in needs_complaints:
		if needs_complaints[need_name] > worst_count:
			worst_count = needs_complaints[need_name]
			worst_need = need_name
	return worst_need

func _exit_tree() -> void:
	# Disconnect signals to prevent memory leaks on reload
	if EventBus.golfer_thought.is_connected(_on_golfer_thought):
		EventBus.golfer_thought.disconnect(_on_golfer_thought)
	if EventBus.day_changed.is_connected(_on_day_changed):
		EventBus.day_changed.disconnect(_on_day_changed)

# Diagnostic records are independent of randomized thought-bubble display.
var incidents: Array = []
var visits: Array = []
var customers: Array = []
var returning_today: int = 0
var service_visits: int = 0
var service_revenue: int = 0
var guest_sequence: int = 0
## Club membership: golfers a member's word of mouth has sent this way but who
## have not arrived yet, and how many it has brought today (see ClubMembership
## and GolferManager.spawn_visiting_golfer).
var referrals_pending: int = 0
var referrals_today: int = 0
## At most this many member referrals wait for an arriving golfer.
const MAX_PENDING_REFERRALS: int = 4

func next_guest_key() -> String:
	guest_sequence += 1
	return "guest-%d" % guest_sequence

func record_incident(golfer, trigger: int) -> void:
	if FeedbackTriggers.get_sentiment(trigger) != "negative": return
	var hole: int = golfer.current_hole + 1
	for item in incidents:
		if item.golfer_id == golfer.golfer_id and item.hole == hole and item.trigger == trigger: return
	var position: Vector2i = GameManager.terrain_grid.screen_to_grid(golfer.global_position) if GameManager.terrain_grid else Vector2i.ZERO
	incidents.append({"golfer_id":golfer.golfer_id,"name":golfer.golfer_name,"hole":hole,"trigger":trigger,"x":position.x,"y":position.y,"day":GameManager.current_day,"needs":golfer.needs.to_dict()})
	if incidents.size() > 500: incidents.pop_front()

func incident_title(trigger: int) -> String:
	match trigger:
		FeedbackTriggers.TriggerType.SLOW_PACE: return "Traffic delay"
		FeedbackTriggers.TriggerType.TIRED: return "Needs a rest"
		FeedbackTriggers.TriggerType.HUNGRY: return "Needs food"
		FeedbackTriggers.TriggerType.NEEDS_RESTROOM: return "Needs a restroom"
		FeedbackTriggers.TriggerType.THIRSTY: return "Needs a drink"
		FeedbackTriggers.TriggerType.OVERPRICED: return "Poor value"
		FeedbackTriggers.TriggerType.HAZARD_WATER: return "Lost a ball in water"
		FeedbackTriggers.TriggerType.SHANK: return "Mishit"
		FeedbackTriggers.TriggerType.BOGEY_PLUS: return "Difficult scoring"
	return "Disappointing round"

func incident_guidance(trigger: int) -> String:
	match trigger:
		FeedbackTriggers.TriggerType.SLOW_PACE: return "Groups ahead blocked play. Reduce tee-time frequency or improve the congested landing area. Normal turns within a group do not count as traffic."
		FeedbackTriggers.TriggerType.TIRED: return "Add reachable seating beside the route. Rest restores energy and helps golfers keep walking comfortably."
		FeedbackTriggers.TriggerType.HUNGRY: return "Add a Snack Bar (or a Pub on a links course) beside the route. Food restores hunger and earns service income."
		FeedbackTriggers.TriggerType.NEEDS_RESTROOM: return "Golfers freshen up at the clubhouse. Keep the clubhouse within reach of the back nine so comfort recovers."
		FeedbackTriggers.TriggerType.THIRSTY: return "Hire a drinks vendor (Soda Vendor or Cart Refresher) and set their area over this stretch so thirsty golfers get served on the course."
		FeedbackTriggers.TriggerType.OVERPRICED: return "The fee exceeded this course's fair-price reference. Poor value reduces return intent."
	return "Inspect this hole's scores and hazards. An occasional bad shot does not by itself mean the design needs changing."

func get_hotspots() -> Array:
	var groups := {}
	for item in incidents:
		var key := "%d:%d" % [item.hole,item.trigger]
		if not groups.has(key):
			groups[key] = item.duplicate(true)
			groups[key]["count"] = 0
		groups[key].count += 1
	var result: Array = groups.values()
	result.sort_custom(func(a,b):
		var actionable := [FeedbackTriggers.TriggerType.SLOW_PACE,FeedbackTriggers.TriggerType.TIRED,FeedbackTriggers.TriggerType.HUNGRY,FeedbackTriggers.TriggerType.NEEDS_RESTROOM,FeedbackTriggers.TriggerType.THIRSTY,FeedbackTriggers.TriggerType.OVERPRICED]
		var a_priority: int = 1000 if int(a.trigger) in actionable else 0
		var b_priority: int = 1000 if int(b.trigger) in actionable else 0
		return a_priority + int(a.count) > b_priority + int(b.count)
	)
	return result.slice(0,3)

func guest_incident_text(id: int) -> String:
	var counts := {}
	var worst: Dictionary = {}
	var most := 0
	for item in incidents:
		if item.golfer_id != id: continue
		counts[item.trigger] = counts.get(item.trigger,0) + 1
		if counts[item.trigger] > most:
			most = counts[item.trigger]
			worst = item
	if worst.is_empty(): return "No complaints recorded this visit."
	return "%s (%d reports), including hole %d (%d,%d). %s" % [incident_title(worst.trigger),most,worst.hole,worst.x,worst.y,incident_guidance(worst.trigger)]

func record_visit(golfer) -> void:
	var key: String = golfer.guest_key
	for item in visits:
		if item.key == key: return
	var holes: int = maxi(golfer._round_total_holes, 1)
	var fair := CourseEconomy.fair_round_price(GameManager.reputation,holes,GameManager.current_day,GameManager.current_theme)
	var value := clampf(fair / maxf(golfer.paid_round_fee,1),0.0,1.0)
	var score := clampf(golfer.needs.get_overall_satisfaction()*.5 + golfer.attitude*.25 + value*.25,0.0,1.0)
	var intent := clampf(score * .9 + value * .1, .05, .95)
	# The round's verdict on the golfer's club membership (see ClubMembership):
	# a good round signs them up or moves them up, a poor one moves them down.
	var membership_result := settle_membership(golfer, key, score, value)
	var new_tier: int = int(membership_result["new"])
	var review := {"key":key,"name":golfer.golfer_name,"score":score,"return_intent":intent,"wait_seconds":golfer.traffic_wait_seconds,"services":golfer.amenities_used,"needs":golfer.needs.to_dict(),"fee":golfer.paid_round_fee,"membership":new_tier,"membership_change":new_tier - int(membership_result["old"]),"membership_reason":str(membership_result["reason"])}
	visits.append(review)
	var profile := {"key":key,"name":golfer.golfer_name,"tier":golfer.golfer_tier,"last_day":GameManager.current_day,"intent":intent,"patience":golfer.patience,"aggression":golfer.aggression,"miss_tendency":golfer.miss_tendency,"membership":new_tier,"membership_reason":str(membership_result["reason"]),"attributes":golfer.attributes.serialize()}
	for i in range(customers.size()-1,-1,-1):
		if customers[i].key == key: customers.remove_at(i)
	customers.append(profile)
	if customers.size() > 200: customers.pop_front()
	# A contented member talks the club up: an arriving golfer may join as a
	# referral instead of the club relying on new traffic.
	attempt_referrals(new_tier, score)

## An eligible prior customer returns for another round: one drawn at random
## from the register whose last visit was before yesterday and whose return
## intent (plus their membership's loyalty) the roll honours. Empty when nobody
## comes back - the caller generates a new guest instead.
func take_returning_guest() -> Dictionary:
	var eligible: Array = []
	for customer in customers:
		if int(customer.last_day) < GameManager.current_day - 1: eligible.append(customer)
	if eligible.is_empty(): return {}
	var selected: Dictionary = eligible[randi() % eligible.size()]
	# Members are the club's regulars: their membership adds to their return
	# intent, so a keen member is likelier to come back than a one-off guest.
	var loyalty := 1.0 + 0.1 * float(int(selected.get("membership", ClubMembership.Tier.NON_MEMBER)))
	if randf() > float(selected.intent) * .5 * loyalty: return {}
	selected.last_day = GameManager.current_day
	returning_today += 1
	return selected.duplicate(true)

# ---------------------------------------------------------------------------
# Club membership (see ClubMembership)
# ---------------------------------------------------------------------------

## How many members the club has, by tier - the readout the HUD and Course
## Review show.
func membership_counts() -> Dictionary:
	var counts := {ClubMembership.Tier.NON_MEMBER: 0}
	for tier in ClubMembership.TIERS:
		counts[tier] = 0
	for customer in customers:
		var tier := int(customer.get("membership", ClubMembership.Tier.NON_MEMBER))
		counts[tier] = counts.get(tier, 0) + 1
	return counts

## The club's member count and the fee premium it represents.
func membership_summary() -> Dictionary:
	var counts := membership_counts()
	var members := 0
	var premium := 0.0
	for tier in ClubMembership.TIERS:
		if tier == ClubMembership.Tier.NON_MEMBER:
			continue
		members += counts[tier]
		premium += ClubMembership.fee_multiplier(tier)
	return {
		"counts": counts,
		"members": members,
		"gold": counts[ClubMembership.Tier.GOLD],
		"silver": counts[ClubMembership.Tier.SILVER],
		"bronze": counts[ClubMembership.Tier.BRONZE],
		"average_fee_multiplier": (premium / members) if members > 0 else 1.0,
		"demand_modifier": ClubMembership.demand_modifier(members),
		"max_tier": ClubMembership.max_tier_for_course(
			float(GameManager.course_rating.get("overall", 3.0)), GameManager.reputation),
	}

## The reason the golfer's last round gave for their membership change (empty
## when it did not move).
func membership_reason_for(key: String) -> String:
	for customer in customers:
		if customer.key == key:
			return str(customer.get("membership_reason", ""))
	return ""

## The membership a known customer holds, by guest key or name. Unknown names
## are Non-members.
func membership_for_customer(key: String, guest_name: String = "") -> int:
	for customer in customers:
		if key != "" and customer.key == key:
			return int(customer.get("membership", ClubMembership.Tier.NON_MEMBER))
		if guest_name != "" and customer.name == guest_name:
			return int(customer.get("membership", ClubMembership.Tier.NON_MEMBER))
	return ClubMembership.Tier.NON_MEMBER

## The membership a visiting-golfer card's owner holds, by name. World-map
## visiting golfers are named people, so their membership follows the name
## across rounds.
func membership_for_guest(guest_name: String) -> int:
	return membership_for_customer("", guest_name)

## Settle the membership after a finished round: work out the new tier, write
## it onto the golfer and their customer profile, bank the joining fee and
## announce the change. Returns {"old": tier, "new": tier, "reason": text}.
func settle_membership(golfer, key: String, satisfaction: float, value: float) -> Dictionary:
	var old_tier := ClubMembership.clamp_tier(int(golfer.membership_tier))
	var ceiling := ClubMembership.max_tier_for_course(
		float(GameManager.course_rating.get("overall", 3.0)), GameManager.reputation)
	# A golfer a member talked into the round is quicker to sign up.
	var boost := ClubMembership.REFERRAL_PROMOTION_BOOST if golfer.referred_by_member else 0.0
	var new_tier := ClubMembership.change_for_round(old_tier, satisfaction, value, ceiling, boost)
	var facts := ClubMembership.round_facts(golfer, satisfaction, value)
	var reason := ClubMembership.reason_for(new_tier - old_tier, facts)
	golfer.membership_tier = new_tier
	for customer in customers:
		if customer.key == key:
			customer.membership = new_tier
			customer.membership_reason = reason
			break
	if new_tier > old_tier:
		var joining := ClubMembership.joining_fee(new_tier)
		if joining > 0:
			GameManager.modify_money(joining)
			GameManager.daily_stats.record_membership_income(joining)
			EventBus.log_transaction("%s paid a %s joining fee" % [
				golfer.golfer_name, ClubMembership.tier_name(new_tier).to_lower()], joining)
	EventBus.membership_changed.emit(golfer.golfer_id, golfer.golfer_name, old_tier, new_tier, reason)
	if new_tier != old_tier and EventFeedManager != null:
		EventFeedManager.announce_membership_change(golfer.golfer_name, old_tier, new_tier, reason)
	return {"old": old_tier, "new": new_tier, "reason": reason}

## The golfer talked the club up after a good round. A member does so with
## their tier's referral chance; a happy guest who just signed up has only
## their new membership's word of mouth to offer, which ClubMembership gives
## them. One roll, one recruit at most, capped so referrals never flood the
## course. A member who just upgraded recruits at the new tier's chance.
func attempt_referrals(member_tier: int, satisfaction: float) -> void:
	var chance := ClubMembership.referral_chance(member_tier, satisfaction)
	if chance <= 0.0 or randf() >= chance:
		return
	referrals_pending = mini(referrals_pending + 1, MAX_PENDING_REFERRALS)

## Whether this arriving golfer was recruited by a member: the member talked
## somebody into a round and this is them. One referral brings one golfer, so
## the pending count is spent whether or not the arrival is named.
func consume_referral(_guest_name: String) -> bool:
	if referrals_pending <= 0:
		return false
	referrals_pending -= 1
	referrals_today += 1
	return true

func visit_summary() -> Dictionary:
	var score := 0.0
	var intent := 0.0
	var wait := 0.0
	for visit in visits:
		score += visit.score
		intent += visit.return_intent
		wait += visit.wait_seconds
	var count := visits.size()
	var members := membership_summary()
	return {"reviews":count,"satisfaction":score/maxi(count,1),"return_intent":intent/maxi(count,1),"traffic_minutes":wait/maxi(count,1)/60.0,"returning":returning_today,"service_visits":service_visits,"service_revenue":service_revenue,"complaints":incidents.size(),"members":members.members,"membership_counts":members.counts,"referrals":referrals_today}

func serialize_experience() -> Dictionary:
	return {"guest_sequence":guest_sequence,"incidents":incidents.duplicate(true),"visits":visits.duplicate(true),"customers":customers.duplicate(true),"returning_today":returning_today,"service_visits":service_visits,"service_revenue":service_revenue,"referrals_pending":referrals_pending,"referrals_today":referrals_today}

func restore_experience(data: Dictionary) -> void:
	guest_sequence = int(data.get("guest_sequence",0))
	incidents = data.get("incidents", []).duplicate(true)
	visits = data.get("visits", []).duplicate(true)
	customers = data.get("customers", []).duplicate(true)
	returning_today = int(data.get("returning_today", 0))
	service_visits = int(data.get("service_visits", 0))
	service_revenue = int(data.get("service_revenue", 0))
	referrals_pending = int(data.get("referrals_pending", 0))
	referrals_today = int(data.get("referrals_today", 0))
	# Saves from before club membership existed carry customer profiles with no
	# tier: everyone starts as a Non-member, the way a new club opens.
	for customer in customers:
		customer.membership = ClubMembership.clamp_tier(
			int(customer.get("membership", ClubMembership.Tier.NON_MEMBER)))

func recent_experience() -> Dictionary:
	var history: Array = GameManager.daily_history.slice(-3)
	var reviews := 0
	var weighted := 0.0
	var profit := 0.0
	for day in history:
		var experience: Dictionary = day.get("guest_experience",{})
		var count: int = int(experience.get("reviews",0))
		reviews += count
		weighted += float(experience.get("satisfaction",0.0)) * count
		profit += float(day.get("profit",0))
	return {"days":history.size(),"reviews":reviews,"satisfaction":weighted/maxi(reviews,1),"profit":profit/maxi(history.size(),1)}
