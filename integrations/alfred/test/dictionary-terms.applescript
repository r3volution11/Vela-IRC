-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- The AppleScript for every Apple event scripts/vela.js sends Vela, as its
-- JXA calls would read in AppleScript. test/vela.test.mjs compiles it
-- against a stand-in app that carries a copy of Vela/Vela.sdef (never
-- against Vela itself, so nothing asks for permission), which fails if a
-- term isn't in Vela's dictionary. VELA_TERMS_APP becomes the stand-in's path.

using terms from application "VELA_TERMS_APP"
	-- list: one Apple event per property (readConversations).
	on listConversations(vela)
		tell vela
			set ids to id of every conversation
			set names to name of every conversation
			set networkNames to network name of every conversation
			set kinds to kind of every conversation
			set unreads to unread count of every conversation
			set mentions to mention count of every conversation
			set joins to joined of every conversation
			set mutes to muted of every conversation
			return {ids, names, networkNames, kinds, unreads, mentions, joins, mutes}
		end tell
	end listConversations

	-- act: what each result does (vela_action).
	on act(vela, conversationID, messageText)
		tell vela
			set target to conversation id conversationID
			show target -- open
			catch up target -- catchup
			catch up -- catchup, Catch Me Up
			open recap target -- recap
			open recap -- recap, Open Recap
			mark read target -- markread
			set counted to mark all read -- markallread
			send message messageText to target -- send
			draft message messageText to target -- draft
			return counted
		end tell
	end act

	on kindValues()
		return {channel, private conversation}
	end kindValues
end using terms from
