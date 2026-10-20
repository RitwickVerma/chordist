.pragma library

// Stands in for KDE's i18n() outside the Plasma shell: substitutes %1, %2 ...
function t(text) {
    var args = Array.prototype.slice.call(arguments, 1)
    return String(text).replace(/%(\d)/g, function (match, n) {
        var value = args[parseInt(n, 10) - 1]
        return value === undefined ? match : value
    })
}
