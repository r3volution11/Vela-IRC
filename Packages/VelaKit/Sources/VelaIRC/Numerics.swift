// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// Numeric reply codes a client cares about, as they appear in
/// `IRCMessage.command`. Names follow the conventional `RPL_`/`ERR_`
/// identifiers (see https://modern.ircdocs.horse/), camel-cased.
public enum IRCNumeric {
    // MARK: Registration
    /// RPL_WELCOME
    public static let welcome = "001"
    /// RPL_YOURHOST
    public static let yourHost = "002"
    /// RPL_CREATED
    public static let created = "003"
    /// RPL_MYINFO
    public static let myInfo = "004"
    /// RPL_ISUPPORT
    public static let isupport = "005"
    /// RPL_BOUNCE (non-standard but common: redirect to another server)
    public static let bounce = "010"

    // MARK: User modes / stats
    /// RPL_UMODEIS
    public static let umodeIs = "221"
    /// RPL_LUSERCLIENT
    public static let luserClient = "251"
    /// RPL_LUSEROP
    public static let luserOp = "252"
    /// RPL_LUSERUNKNOWN
    public static let luserUnknown = "253"
    /// RPL_LUSERCHANNELS
    public static let luserChannels = "254"
    /// RPL_LUSERME
    public static let luserMe = "255"
    /// RPL_ADMINME
    public static let adminMe = "256"
    /// RPL_LOCALUSERS
    public static let localUsers = "265"
    /// RPL_GLOBALUSERS
    public static let globalUsers = "266"
    /// RPL_WHOISCERTFP
    public static let whoisCertFP = "276"

    // MARK: Away / WHOIS / WHOWAS
    /// RPL_AWAY
    public static let away = "301"
    /// RPL_USERHOST
    public static let userHost = "302"
    /// RPL_ISON
    public static let isOn = "303"
    /// RPL_UNAWAY
    public static let unaway = "305"
    /// RPL_NOWAWAY
    public static let nowAway = "306"
    /// RPL_WHOISREGNICK
    public static let whoisRegNick = "307"
    /// RPL_WHOISUSER
    public static let whoisUser = "311"
    /// RPL_WHOISSERVER
    public static let whoisServer = "312"
    /// RPL_WHOISOPERATOR
    public static let whoisOperator = "313"
    /// RPL_WHOWASUSER
    public static let whowasUser = "314"
    /// RPL_ENDOFWHO
    public static let endOfWho = "315"
    /// RPL_WHOISIDLE
    public static let whoisIdle = "317"
    /// RPL_ENDOFWHOIS
    public static let endOfWhois = "318"
    /// RPL_WHOISCHANNELS
    public static let whoisChannels = "319"
    /// RPL_WHOISSPECIAL
    public static let whoisSpecial = "320"
    /// RPL_LISTSTART
    public static let listStart = "321"
    /// RPL_LIST
    public static let list = "322"
    /// RPL_LISTEND
    public static let listEnd = "323"
    /// RPL_CHANNELMODEIS
    public static let channelModeIs = "324"
    /// RPL_CREATIONTIME
    public static let creationTime = "329"
    /// RPL_WHOISACCOUNT
    public static let whoisAccount = "330"
    /// RPL_NOTOPIC
    public static let noTopic = "331"
    /// RPL_TOPIC
    public static let topic = "332"
    /// RPL_TOPICWHOTIME
    public static let topicWhoTime = "333"
    /// RPL_WHOISACTUALLY
    public static let whoisActually = "338"
    /// RPL_INVITING
    public static let inviting = "341"
    /// RPL_INVITELIST
    public static let inviteList = "346"
    /// RPL_ENDOFINVITELIST
    public static let endOfInviteList = "347"
    /// RPL_EXCEPTLIST
    public static let exceptList = "348"
    /// RPL_ENDOFEXCEPTLIST
    public static let endOfExceptList = "349"
    /// RPL_VERSION
    public static let version = "351"
    /// RPL_WHOREPLY
    public static let whoReply = "352"
    /// RPL_NAMREPLY
    public static let namReply = "353"
    /// RPL_WHOSPCRPL (WHOX)
    public static let whoxReply = "354"
    /// RPL_ENDOFNAMES
    public static let endOfNames = "366"
    /// RPL_BANLIST
    public static let banList = "367"
    /// RPL_ENDOFBANLIST
    public static let endOfBanList = "368"
    /// RPL_ENDOFWHOWAS
    public static let endOfWhowas = "369"
    /// RPL_INFO
    public static let info = "371"
    /// RPL_MOTD
    public static let motd = "372"
    /// RPL_ENDOFINFO
    public static let endOfInfo = "374"
    /// RPL_MOTDSTART
    public static let motdStart = "375"
    /// RPL_ENDOFMOTD
    public static let endOfMotd = "376"
    /// RPL_WHOISHOST
    public static let whoisHost = "378"
    /// RPL_WHOISMODES
    public static let whoisModes = "379"
    /// RPL_YOUREOPER
    public static let youreOper = "381"
    /// RPL_TIME
    public static let time = "391"

    // MARK: Errors
    /// ERR_UNKNOWNERROR
    public static let unknownError = "400"
    /// ERR_NOSUCHNICK
    public static let noSuchNick = "401"
    /// ERR_NOSUCHSERVER
    public static let noSuchServer = "402"
    /// ERR_NOSUCHCHANNEL
    public static let noSuchChannel = "403"
    /// ERR_CANNOTSENDTOCHAN
    public static let cannotSendToChan = "404"
    /// ERR_TOOMANYCHANNELS
    public static let tooManyChannels = "405"
    /// ERR_WASNOSUCHNICK
    public static let wasNoSuchNick = "406"
    /// ERR_NORECIPIENT
    public static let noRecipient = "411"
    /// ERR_NOTEXTTOSEND
    public static let noTextToSend = "412"
    /// ERR_INPUTTOOLONG
    public static let inputTooLong = "417"
    /// ERR_UNKNOWNCOMMAND
    public static let unknownCommand = "421"
    /// ERR_NOMOTD
    public static let noMotd = "422"
    /// ERR_NONICKNAMEGIVEN
    public static let noNicknameGiven = "431"
    /// ERR_ERRONEUSNICKNAME
    public static let erroneousNickname = "432"
    /// ERR_NICKNAMEINUSE
    public static let nicknameInUse = "433"
    /// ERR_NICKCOLLISION
    public static let nickCollision = "436"
    /// ERR_UNAVAILRESOURCE (nick/channel temporarily unavailable)
    public static let unavailableResource = "437"
    /// ERR_USERNOTINCHANNEL
    public static let userNotInChannel = "441"
    /// ERR_NOTONCHANNEL
    public static let notOnChannel = "442"
    /// ERR_USERONCHANNEL
    public static let userOnChannel = "443"
    /// ERR_NOTREGISTERED
    public static let notRegistered = "451"
    /// ERR_NEEDMOREPARAMS
    public static let needMoreParams = "461"
    /// ERR_ALREADYREGISTERED
    public static let alreadyRegistered = "462"
    /// ERR_PASSWDMISMATCH
    public static let passwordMismatch = "464"
    /// ERR_YOUREBANNEDCREEP
    public static let youreBannedCreep = "465"
    /// ERR_CHANNELISFULL
    public static let channelIsFull = "471"
    /// ERR_UNKNOWNMODE
    public static let unknownMode = "472"
    /// ERR_INVITEONLYCHAN
    public static let inviteOnlyChan = "473"
    /// ERR_BANNEDFROMCHAN
    public static let bannedFromChan = "474"
    /// ERR_BADCHANNELKEY
    public static let badChannelKey = "475"
    /// ERR_BADCHANMASK
    public static let badChanMask = "476"
    /// ERR_NEEDREGGEDNICK (common usage; some servers use 477 as ERR_NOCHANMODES)
    public static let needReggedNick = "477"
    /// ERR_NOPRIVILEGES
    public static let noPrivileges = "481"
    /// ERR_CHANOPRIVSNEEDED
    public static let chanOpPrivsNeeded = "482"
    /// ERR_UMODEUNKNOWNFLAG
    public static let umodeUnknownFlag = "501"
    /// ERR_USERSDONTMATCH
    public static let usersDontMatch = "502"

    // MARK: TLS
    /// RPL_STARTTLS
    public static let startTLS = "670"
    /// RPL_WHOISSECURE
    public static let whoisSecure = "671"
    /// ERR_STARTTLS
    public static let startTLSFailed = "691"

    // MARK: Help
    /// RPL_HELPSTART
    public static let helpStart = "704"
    /// RPL_HELPTXT
    public static let helpText = "705"
    /// RPL_ENDOFHELP
    public static let endOfHelp = "706"

    // MARK: MONITOR
    /// RPL_MONONLINE
    public static let monitorOnline = "730"
    /// RPL_MONOFFLINE
    public static let monitorOffline = "731"
    /// RPL_MONLIST
    public static let monitorList = "732"
    /// RPL_ENDOFMONLIST
    public static let endOfMonitorList = "733"
    /// ERR_MONLISTFULL
    public static let monitorListFull = "734"

    // MARK: SASL
    /// RPL_LOGGEDIN
    public static let loggedIn = "900"
    /// RPL_LOGGEDOUT
    public static let loggedOut = "901"
    /// ERR_NICKLOCKED
    public static let nickLocked = "902"
    /// RPL_SASLSUCCESS
    public static let saslSuccess = "903"
    /// ERR_SASLFAIL
    public static let saslFail = "904"
    /// ERR_SASLTOOLONG
    public static let saslTooLong = "905"
    /// ERR_SASLABORTED
    public static let saslAborted = "906"
    /// ERR_SASLALREADY
    public static let saslAlready = "907"
    /// RPL_SASLMECHS
    public static let saslMechanisms = "908"

    /// Numerics in the 400–599 range are errors.
    public static func isError(_ command: String) -> Bool {
        guard command.utf8.count == 3, let value = Int(command) else { return false }
        return (400..<600).contains(value)
    }
}
