--!strict

return table.freeze({
	CacheIds = table.freeze({ "A", "B", "C" }),
	ManualRange = 8,
	ScannerRange = 30,
	ExtractRange = 8,
	ObservationSeconds = 6,
	SignalCycleSeconds = 6,
	SignalPulseSeconds = 0.22,
	SignalPatterns = table.freeze({
		table.freeze({ 0, 1.5, 3, 4.5 }), -- even intervals, including cycle boundary
		table.freeze({ 0, 0.6, 3, 4.5 }),
		table.freeze({ 0, 1.5, 2.1, 4.5 }),
	}),
	ExtractSeconds = 0.8,
	WrongRetrySeconds = 2,
	RequestInterval = 0.3,
	ActivityMargin = 4,
	AbandonmentGraceSeconds = 3,
	InactivitySeconds = 25,
	AbsoluteInvestigationLeaseSeconds = 60,
	ReservationPollSeconds = 0.5,
	ActivityMovementStuds = 2,
	ChaseTimeout = 60,
	HeadStartSeconds = 2.5,
	WardenSpeed = 15,
	CatchRadius = 3.5,
	PollSeconds = 0.1,
	ResetSeconds = 3,
	SuccessCooldown = 20,
	RewardSpeciesId = "Conejurer",
})
