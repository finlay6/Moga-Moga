local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Packages = Shared.Packages
local Signal = require(Packages.Signal)

local QuestSignals = {}

QuestSignals.StageActivated = Signal()
QuestSignals.QuestGiven = Signal()
QuestSignals.QuestCompleted = Signal()
QuestSignals.Quest = Signal()
QuestSignals.QuestGiven = Signal()
QuestSignals.QuestGiven = Signal()


return QuestSignals
