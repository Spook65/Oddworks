--!strict

export type SignatureDiscoveryDefinition = {
	OpportunityId: string,
	SignatureId: string,
	WorldModelName: string,
	InteractionPartName: string,
	CueAnchorName: string,
	RevealMarkerNamesByPlot: { [string]: string },
	TemplateName: string,
	MaxValidDistance: number,
	AttemptIntervalSeconds: number,
	AuditIntervalSeconds: number,
}

local SignatureDiscoveryConfig = {}

local definition: SignatureDiscoveryDefinition = {
	OpportunityId = "KilnbackSignal",
	SignatureId = "Kilnback",
	WorldModelName = "HiddenSignalOpportunity",
	InteractionPartName = "InvestigationConsole",
	CueAnchorName = "SignalCueAnchor",
	RevealMarkerNamesByPlot = {
		Plot01 = "KilnbackRevealPlot01",
		Plot02 = "KilnbackRevealPlot02",
	},
	TemplateName = "Kilnback_Prototype",
	MaxValidDistance = 10,
	AttemptIntervalSeconds = 0.75,
	AuditIntervalSeconds = 2,
}

function SignatureDiscoveryConfig.GetDefinition(): SignatureDiscoveryDefinition
	return {
		OpportunityId = definition.OpportunityId,
		SignatureId = definition.SignatureId,
		WorldModelName = definition.WorldModelName,
		InteractionPartName = definition.InteractionPartName,
		CueAnchorName = definition.CueAnchorName,
		RevealMarkerNamesByPlot = table.clone(definition.RevealMarkerNamesByPlot),
		TemplateName = definition.TemplateName,
		MaxValidDistance = definition.MaxValidDistance,
		AttemptIntervalSeconds = definition.AttemptIntervalSeconds,
		AuditIntervalSeconds = definition.AuditIntervalSeconds,
	}
end

return SignatureDiscoveryConfig
