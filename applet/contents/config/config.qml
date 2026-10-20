// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
//
// SPDX-License-Identifier: MIT

import QtQuick 2.0
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "configure"
        source: "config/General.qml"
    }
}
