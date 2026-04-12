--!strict
-- ReplicatedStorage/Shared/Constants/Player/NametagConstants.luau

--[[
	NametagConstants

	Configuration for the billboard nametag system.

	─── Billboard template ─────────────────────────────────────────────
	The template BillboardGui lives at:
	  ReplicatedStorage/Assets/UI/NametagTemplate

	Expected children:
	  NametagTemplate (BillboardGui)
	    Frame (Frame)
	      BadgeIcon   (ImageLabel)   ← star / rank icon above the name
	      NameLabel   (TextLabel)    ← display name
	      CountryLabel(TextLabel)    ← country below the name
	      RankLabel   (TextLabel)    ← rank label e.g. "Admin", hidden if empty
]]

local NametagConstants = {
	COUNTRIES = {} :: {string},
	UIConstants = {} :: {any}
}

-- ─── Billboard sizing ─────────────────────────────────────────────────────────

NametagConstants.UIConstants = {
	BILLBOARD_SIZE         = UDim2.fromScale(5, 2),  -- scale
	BILLBOARD_STUD_OFFSET  = Vector3.new(0, 2.5, 0),
	BILLBOARD_MAX_DISTANCE = math.huge  -- studs
}

-- ─── Template path ────────────────────────────────────────────────────────────
-- Relative to ReplicatedStorage. NametagService resolves this on init.

NametagConstants.TEMPLATE_PATH = "UI.Components.NametagTemplate"

-- ─── Default values ───────────────────────────────────────────────────────────

NametagConstants.DEFAULT_COUNTRY     = "Unknown"
NametagConstants.DEFAULT_NAME_COLOR  = Color3.fromRGB(255, 255, 255)
NametagConstants.DEFAULT_BADGE_COLOR = Color3.fromRGB(255, 255, 255)

-- ─── Countries ────────────────────────────────────────────────────────────────
-- Used to populate the country dropdown on first join.
-- Sorted alphabetically for the dropdown. Add or remove as needed.

NametagConstants.COUNTRIES = {
	"Afghanistan", "Albania", "Algeria", "Andorra", "Angola", "Argentina",
	"Armenia", "Australia", "Austria", "Azerbaijan", "Bahamas", "Bahrain",
	"Bangladesh", "Belarus", "Belgium", "Belize", "Benin", "Bhutan",
	"Bolivia", "Bosnia and Herzegovina", "Botswana", "Brazil", "Brunei",
	"Bulgaria", "Burkina Faso", "Burundi", "Cambodia", "Cameroon", "Canada",
	"Central African Republic", "Chad", "Chile", "China", "Colombia",
	"Comoros", "Congo", "Costa Rica", "Croatia", "Cuba", "Cyprus",
	"Czech Republic", "Denmark", "Djibouti", "Dominican Republic", "Ecuador",
	"Egypt", "El Salvador", "Equatorial Guinea", "Eritrea", "Estonia",
	"Eswatini", "Ethiopia", "Fiji", "Finland", "France", "Gabon", "Gambia",
	"Georgia", "Germany", "Ghana", "Greece", "Guatemala", "Guinea",
	"Guinea-Bissau", "Guyana", "Haiti", "Honduras", "Hungary", "Iceland",
	"India", "Indonesia", "Iran", "Iraq", "Ireland", "Israel", "Italy",
	"Jamaica", "Japan", "Jordan", "Kazakhstan", "Kenya", "Kuwait",
	"Kyrgyzstan", "Laos", "Latvia", "Lebanon", "Lesotho", "Liberia",
	"Libya", "Liechtenstein", "Lithuania", "Luxembourg", "Madagascar",
	"Malawi", "Malaysia", "Maldives", "Mali", "Malta", "Mauritania",
	"Mauritius", "Mexico", "Moldova", "Monaco", "Mongolia", "Montenegro",
	"Morocco", "Mozambique", "Myanmar", "Namibia", "Nepal", "Netherlands",
	"New Zealand", "Nicaragua", "Niger", "Nigeria", "North Korea",
	"North Macedonia", "Norway", "Oman", "Pakistan", "Panama",
	"Papua New Guinea", "Paraguay", "Peru", "Philippines", "Poland",
	"Portugal", "Qatar", "Romania", "Russia", "Rwanda", "Saudi Arabia",
	"Senegal", "Serbia", "Sierra Leone", "Singapore", "Slovakia", "Slovenia",
	"Somalia", "South Africa", "South Korea", "South Sudan", "Spain",
	"Sri Lanka", "Sudan", "Suriname", "Sweden", "Switzerland", "Syria",
	"Taiwan", "Tajikistan", "Tanzania", "Thailand", "Timor-Leste", "Togo",
	"Trinidad and Tobago", "Tunisia", "Turkey", "Turkmenistan", "Uganda",
	"Ukraine", "United Arab Emirates", "United Kingdom", "United States",
	"Uruguay", "Uzbekistan", "Venezuela", "Vietnam", "Yemen", "Zambia",
	"Zimbabwe",
}

return table.freeze(NametagConstants)
