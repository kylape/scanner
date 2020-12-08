package features

var (
	LanguageVulns = registerFeature("Enable language vulnerabilities", "ROX_LANGUAGE_VULNS", true, NoRoxAllowed())

	ContinueUnknownOS = registerFeature("Enable continuation upon detecting unknown OS", "ROX_CONTINUE_UNKNOWN_OS", true)

	SkipPeerValidation = registerFeature("Skip peer certificate validation. Typically used for testing", "ROX_SKIP_PEER_VALIDATION", false)
)
