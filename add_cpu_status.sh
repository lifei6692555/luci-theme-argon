#!/bin/bash
#
# add_cpu_status.sh - 为 luci-theme-argon 添加 CPU 温度和使用率显示
#
# 使用方法:
#   方式一 (自动克隆原作者源码并添加):
#     ./add_cpu_status.sh
#
#   方式二 (指定已克隆的 luci-theme-argon 目录):
#     ./add_cpu_status.sh /path/to/luci-theme-argon
#
# 说明:
#   此脚本会在 luci-theme-argon 主题中添加 CPU 温度和使用率显示模块。
#   添加后，OpenWrt LuCI 首页（状态 → 概览）将显示：
#     - CPU 使用率（进度条）
#     - CPU 温度（°C）
#
#   原理：LuCI 的状态概览页面会自动加载 view/status/include/ 目录下的 JS 文件，
#   文件名前缀数字决定显示顺序：10_system, 15_cpuinfo, 20_memory, ...
#

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 确定目标目录
if [ -n "$1" ]; then
    THEME_DIR="$1"
else
    # 默认：在当前目录下克隆原作者源码
    THEME_DIR="luci-theme-argon"
    if [ -d "$THEME_DIR" ]; then
        info "luci-theme-argon 目录已存在，直接使用"
    else
        info "正在克隆原作者源码 jerrykuku/luci-theme-argon ..."
        git clone https://github.com/jerrykuku/luci-theme-argon.git "$THEME_DIR"
    fi
fi

# 检查目标目录是否存在
if [ ! -d "$THEME_DIR" ]; then
    error "目录 $THEME_DIR 不存在"
fi

# 检查是否是有效的 luci-theme-argon 目录
if [ ! -f "$THEME_DIR/Makefile" ]; then
    error "$THEME_DIR 不是有效的 luci-theme-argon 源码目录（缺少 Makefile）"
fi

info "目标目录: $THEME_DIR"

# ============================================================
# 1. 创建 CPU 状态显示模块 (15_cpuinfo.js)
# ============================================================
JS_DIR="$THEME_DIR/htdocs/luci-static/resources/view/status/include"
JS_FILE="$JS_DIR/15_cpuinfo.js"

mkdir -p "$JS_DIR"

if [ -f "$JS_FILE" ]; then
    warn "文件 $JS_FILE 已存在，将覆盖"
fi

cat > "$JS_FILE" << 'JSEOF'
'use strict';
'require baseclass';
'require fs';
'require rpc';

var callSystemInfo = rpc.declare({
	object: 'system',
	method: 'info'
});

function progressbar(value, max) {
	var vn = parseInt(value) || 0,
	    mn = parseInt(max) || 100,
	    pc = Math.floor((100 / mn) * vn);

	return E('div', {
		'class': 'cbi-progressbar',
		'title': '%d%% (%d / %d)'.format(pc, vn, mn)
	}, E('div', { 'style': 'width:%.2f%%'.format(pc) }));
}

return baseclass.extend({
	title: _('CPU'),

	prevIdle: 0,
	prevTotal: 0,

	load: function() {
		return Promise.all([
			L.resolveDefault(fs.exec('/bin/cat', ['/sys/class/thermal/thermal_zone0/temp']), null),
			L.resolveDefault(fs.exec('/usr/bin/head', ['-1', '/proc/stat']), null),
			L.resolveDefault(callSystemInfo(), {})
		]);
	},

	render: function(data) {
		var tempResult = data[0],
		    statResult = data[1],
		    systemInfo = data[2];

		var fields = [];

		// Parse CPU temperature
		var cpuTemp = null;
		if (tempResult && tempResult.code === 0 && tempResult.stdout) {
			var temp = parseInt(tempResult.stdout.trim());
			if (!isNaN(temp) && temp > 0) {
				cpuTemp = (temp / 1000).toFixed(1);
			}
		}

		// Parse CPU usage
		var cpuUsage = null;
		if (statResult && statResult.code === 0 && statResult.stdout) {
			var line = statResult.stdout.trim();
			if (line.indexOf('cpu ') === 0) {
				var parts = line.split(/\s+/);
				var user = parseInt(parts[1]) || 0;
				var nice = parseInt(parts[2]) || 0;
				var system = parseInt(parts[3]) || 0;
				var idle = parseInt(parts[4]) || 0;
				var iowait = parseInt(parts[5]) || 0;
				var irq = parseInt(parts[6]) || 0;
				var softirq = parseInt(parts[7]) || 0;
				var steal = parseInt(parts[8]) || 0;

				var idleTime = idle + iowait;
				var totalTime = user + nice + system + idle + iowait + irq + softirq + steal;

				var diffIdle = idleTime - this.prevIdle;
				var diffTotal = totalTime - this.prevTotal;

				if (diffTotal > 0 && this.prevTotal > 0) {
					cpuUsage = Math.round((1 - diffIdle / diffTotal) * 100);
				} else if (this.prevTotal === 0) {
					cpuUsage = 0;
				}

				this.prevIdle = idleTime;
				this.prevTotal = totalTime;
			}
		}

		// Fallback: use load average
		if (cpuUsage === null && systemInfo && systemInfo.load) {
			var load1 = systemInfo.load[0] / 65535.0;
			cpuUsage = Math.min(Math.round(load1 * 100), 100);
		}

		// CPU usage
		if (cpuUsage !== null) {
			fields.push(_('CPU usage (%)'));
			fields.push(progressbar(cpuUsage, 100));
		}

		// CPU temperature
		if (cpuTemp !== null) {
			fields.push(_('Temperature'));
			fields.push(cpuTemp + ' °C');
		}

		if (fields.length === 0) {
			return null;
		}

		var table = E('table', { 'class': 'table' });

		for (var i = 0; i < fields.length; i += 2) {
			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '33%' }, [ fields[i] ]),
				E('td', { 'class': 'td left' }, [
					(fields[i + 1] != null) ? fields[i + 1] : '?'
				])
			]));
		}

		return table;
	}
});
JSEOF

info "✓ 已创建 CPU 状态模块: $JS_FILE"

# ============================================================
# 2. 更新 ACL 配置文件，添加读取 CPU 信息的权限
# ============================================================
ACL_FILE="$THEME_DIR/root/usr/share/rpcd/acl.d/luci-theme-argon.json"

if [ -f "$ACL_FILE" ]; then
    # 检查是否已经包含 thermal 权限
    if grep -q "thermal_zone" "$ACL_FILE"; then
        info "ACL 文件已包含温度读取权限，跳过"
    else
        info "更新 ACL 配置文件，添加 CPU 信息读取权限..."
        cat > "$ACL_FILE" << 'ACLEOF'
{
    "luci-theme-argon": {
        "description": "Grant UCI access for luci-theme-argon",
        "read": {
            "uci": [ "argon" ],
            "file": {
                "/bin/cat /sys/class/thermal/thermal_zone*/temp": [ "exec" ],
                "/usr/bin/head -1 /proc/stat": [ "exec" ]
            }
        }
    }
}
ACLEOF
        info "✓ ACL 配置已更新: $ACL_FILE"
    fi
else
    error "ACL 文件不存在: $ACL_FILE"
fi

# ============================================================
# 完成
# ============================================================
echo ""
info "========================================="
info "  CPU 温度和使用率显示已成功添加！"
info "========================================="
echo ""
info "添加的文件:"
info "  1. $JS_FILE"
info "     -> CPU 使用率（进度条）和温度（°C）显示"
info "  2. $ACL_FILE"
info "     -> 添加读取温度和 CPU 统计的权限"
echo ""
info "编译固件后，在 LuCI 首页（状态 → 概览）即可看到："
info "  - CPU 使用率进度条"
info "  - CPU 温度（如果设备支持）"
echo ""
