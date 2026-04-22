.pragma library

function duration(secs) {
    if (!secs) return "0:00"
    var m = Math.floor(secs / 60)
    var s = secs % 60
    return m + ":" + (s < 10 ? "0" : "") + s
}

function relativeTime(ms) {
    if (!ms) return ""
    var now = Date.now()
    var diff = Math.max(0, now - ms)
    var sec = Math.floor(diff / 1000)
    if (sec < 60) return sec + " 秒前"
    var min = Math.floor(sec / 60)
    if (min < 60) return min + " 分钟前"
    var hr = Math.floor(min / 60)
    if (hr < 24) return hr + " 小时前"
    var day = Math.floor(hr / 24)
    if (day < 30) return day + " 天前"
    var mon = Math.floor(day / 30)
    if (mon < 12) return mon + " 个月前"
    return Math.floor(mon / 12) + " 年前"
}

function absoluteTime(ms) {
    if (!ms) return ""
    var d = new Date(ms)
    var pad = function(n) { return n < 10 ? "0" + n : "" + n }
    return d.getFullYear() + "-" + pad(d.getMonth()+1) + "-" + pad(d.getDate())
         + " " + pad(d.getHours()) + ":" + pad(d.getMinutes())
}

function bigNum(n) {
    if (!n) return "0"
    if (n >= 1000000) return (n/1000000).toFixed(1) + "M"
    if (n >= 1000) return (n/1000).toFixed(1) + "k"
    return "" + n
}

function kdaRatio(k, d, a) {
    if (!d) return "∞"
    return ((k + a) / d).toFixed(2)
}

function kdaColor(ratio) {
    if (ratio >= 5) return "#d4a04a"
    if (ratio >= 3) return "#3ea04a"
    if (ratio >= 2) return "#4684d4"
    if (ratio >= 1) return "#7a7a7a"
    return "#c64343"
}
