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
					(fields[i + 1] !== null) ? fields[i + 1] : '?'
				])
			]));
		}

		return table;
	}
});
