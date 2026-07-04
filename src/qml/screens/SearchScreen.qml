import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import JellyfinDesktop

// Search (jellyfin-web): type-grouped result sections over parallel queries
// (main Items + People + Studios + misc Videos), with web's pre-query
// "Suggestions" panel. Sections follow web's order and card shapes.
Item {
    id: screen
    property var client
    property string pageTitle: qsTr("Search")

    signal itemActivated(var item)
    signal itemOpenDetail(var item)
    signal itemAddToPlaylist(var item)
    signal itemAddToCollection(var item)
    signal cardAction(string verb, var item)

    property var mainResults: []
    property var peopleResults: []
    property var studioResults: []
    property var videoResults: []
    property var suggestions: []
    property int _pending: 0 // in-flight queries (so "No results" waits)

    // web's section order (consumer subset), built from the four result sets
    readonly property var sections: {
        var byType = {}
        for (var i = 0; i < mainResults.length; ++i) {
            var t = mainResults[i].type
            if (!byType[t]) byType[t] = []
            byType[t].push(mainResults[i])
        }
        var out = []
        function add(title, items, shape) { if (items && items.length > 0) out.push({ title: title, items: items, shape: shape }) }
        add(qsTr("Movies"), byType["Movie"], "poster")
        add(qsTr("Shows"), byType["Series"], "poster")
        add(qsTr("Episodes"), byType["Episode"], "thumb")
        add(qsTr("People"), peopleResults, "poster")
        add(qsTr("Studios"), studioResults, "thumb")
        add(qsTr("Playlists"), byType["Playlist"], "poster")
        add(qsTr("Videos"), videoResults, "poster")
        add(qsTr("Collections"), byType["BoxSet"], "poster")
        return out
    }
    readonly property bool showSuggestions: field.text.trim().length === 0
    readonly property bool noResults: !showSuggestions && _pending === 0 && sections.length === 0

    Component.onCompleted: {
        field.forceActiveFocus()
        if (client) client.fetchSearchSuggestions("search:suggest")
    }
    function doSearch(q) {
        const query = q.trim()
        if (!client || query.length === 0) {
            screen.mainResults = []; screen.peopleResults = []
            screen.studioResults = []; screen.videoResults = []
            screen._pending = 0
            return
        }
        screen._pending = 4
        client.search(query, "search:items")
        client.searchPeople(query, "search:people")
        client.searchStudios(query, "search:studios")
        client.searchVideos(query, "search:videos")
    }

    Connections {
        target: screen.client
        function onItemsReady(tag, its) {
            if (tag === "search:items") { screen.mainResults = its; screen._pending-- }
            else if (tag === "search:people") { screen.peopleResults = its; screen._pending-- }
            else if (tag === "search:studios") { screen.studioResults = its; screen._pending-- }
            else if (tag === "search:videos") { screen.videoResults = its; screen._pending-- }
            else if (tag === "search:suggest") screen.suggestions = its
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacing

        // search field
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.pagePad
            Layout.rightMargin: Theme.pagePad
            Layout.topMargin: Theme.spacing
            implicitHeight: Theme.controlHeight
            radius: Theme.radius
            color: Theme.surface
            border.color: field.activeFocus ? Theme.accent : Theme.divider
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacing
                anchors.rightMargin: Theme.spacingSmall
                spacing: Theme.spacingSmall
                Text { text: "\u{1F50D}"; color: Theme.textSecondary; font.pixelSize: Theme.fontNormal }
                TextField {
                    id: field
                    Layout.fillWidth: true
                    placeholderText: qsTr("Search")
                    maximumLength: 40 // web parity
                    color: Theme.textPrimary
                    placeholderTextColor: Theme.textDisabled
                    font.pixelSize: Theme.fontNormal
                    background: Item {}
                    onTextChanged: debounce.restart()
                    onAccepted: screen.doSearch(text)
                }
                JIconButton {
                    text: "✕"
                    visible: field.text.length > 0
                    implicitWidth: 32; implicitHeight: 32
                    onClicked: { field.clear(); screen.doSearch("") }
                }
            }
        }

        Timer { id: debounce; interval: 500; onTriggered: screen.doSearch(field.text) } // web: 500ms

        Text {
            visible: screen.noResults
            text: qsTr("No results for \"%1\"").arg(field.text.trim())
            color: Theme.textSecondary
            font.pixelSize: Theme.fontNormal
            Layout.leftMargin: Theme.pagePad
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: resultsCol.implicitHeight + Theme.spacingLarge
            clip: true
            ScrollBar.vertical: ScrollBar {}

            ColumnLayout {
                id: resultsCol
                width: parent.width
                spacing: Theme.spacingLarge

                // pre-query suggestions (web's SearchSuggestions panel)
                ColumnLayout {
                    visible: screen.showSuggestions && screen.suggestions.length > 0
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.pagePad
                    spacing: 2
                    Text {
                        text: qsTr("Suggestions")
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontMedium
                        font.bold: true
                        Layout.bottomMargin: Theme.spacingSmall
                    }
                    Repeater {
                        model: screen.showSuggestions ? screen.suggestions : []
                        Text {
                            required property var modelData
                            text: modelData.name
                            color: sugHover.hovered ? Theme.accent : Theme.textSecondary
                            font.pixelSize: Theme.fontNormal
                            HoverHandler { id: sugHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: screen.itemOpenDetail(modelData) }
                        }
                    }
                }

                // type-grouped result rows
                Repeater {
                    model: screen.showSuggestions ? [] : screen.sections
                    MediaRow {
                        required property var modelData
                        Layout.fillWidth: true
                        title: modelData.title
                        model: modelData.items
                        client: screen.client
                        shape: modelData.shape
                        onItemActivated: (it) => screen.itemActivated(it)
                        onItemOpenDetail: (it) => screen.itemOpenDetail(it)
                        onItemAddToPlaylist: (it) => screen.itemAddToPlaylist(it)
                        onItemAddToCollection: (it) => screen.itemAddToCollection(it)
                        onCardAction: (verb, it) => screen.cardAction(verb, it)
                    }
                }
            }
        }
    }
}
