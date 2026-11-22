<template>
  <div class="container">
    <div class="item">
      <h4 v-if="peers.length">SSDP Devices</h4>
      <p v-for="peer in peers" v-bind:key="peer.url"><a target="_blank" v-bind:href="peer.url">{{peer.name}}</a></p>
    </div>
    <div class="item">
      <h4>Current Device</h4>
      <p>Uptime: {{ formattedUptime }}</p>
      <p>Release: {{build}}</p>
      <p>IP address: {{ip}}</p>
      <p>MAC address: {{mac}}</p>
      <p>MQTT server: {{mqtthost}}</p>
      <p>MQTT topic: {{mqtttopic}}</p>
      <p>Device short name: {{shortName}}</p>
      <p>Web app URL root: {{webapp}}</p>
      <p>Chipset: {{chipset}}</p>
      <p>Flags: {{flags}}</p>
      <p>Version: {{currentversion}} <span v-html="lateststr"></span></p>
      <p v-if="error">Error: {{error}}</p>
      <h4>Export Current Template</h4>
      <p>Please complete all missing details before submitting a new template to <a href="https://www.elektroda.com/rtvforum/forum390.html" target="_blank" rel="noopener noreferrer">Elektroda</a>.</p>
	  <textarea id="deviceTemplate"  placeholder="Template will appear here. If this box is empty, template generation may have failed." style="vertical-align: top; width: 300px; height:500px"></textarea>
    <br>
          <button @click="getTemplateAsFile">Download template</button>
          <button @click="getTemplateAsClipboard">Copy to clipboard</button>

    </div>

    <div class="item" style="width: 300px;">
      <h4>Pin Settings</h4>
	  <p>Configure your device pins here. Note that some pin roles require a second channel field, which is currently only available in the native UI. LED channel order is R, G, B, C, W (first channel is Red, second is Green, etc.).</p>
      <div v-for="(role, index) in pins.roles" :key="index">
        <span class="pin-index">{{index}}</span>
        <select v-model="pins.roles[index]">
          <option v-for="(name, index2) in pins.rolenames" :value="index2" :key="index2" :selected="(role == index2)">{{name}}</option>
        </select>
        <input type="number" min="0" max="32" step="1" v-model="pins.channels[index]">
      </div>

      <br/>
      <label for="deviceFlag" style="width:75px; display: inline-block;">Flags:</label>&nbsp;<input id="deviceFlag" v-model="deviceFlag" /><br/>
      <label for="deviceCommand" style="width:75px; display: inline-block;">Command:</label>&nbsp;<input id="deviceCommand" v-model="deviceCommand" placeholder="Startup command"/><br/>

      <button @click="savePins">Save pin settings</button>
      <br/>
	  You may need to reboot the device for changes to take effect.
    </div>
    <div class="item" style="width: 300px;">
      <h4>Channel Types</h4>
	  <p>Channel types/roles are primarily used with TuyaMCU devices and are intended for advanced users. They are also useful for creating advanced scriptable devices and for testing.</p>
	  <p>Setting a type for given channel may cause a special control to appear on the main web UI page. For example, a slider for dimmer channel or a radio selection box for a fan speed channel.</p>
	  <p>Do not change these settings unless you understand the implications.</p>
      <div v-for="(role, index) in channelTypes.types" :key="index">
        <span class="channel-index">{{index}}</span>
        <select v-model="channelTypes.types[index]">
          <option v-for="(name, index2) in channelTypes.typenames" :value="index2" :key="index2" :selected="(role == index2)">{{name}}</option>
        </select>
      </div>

      <br/>
      <button @click="saveChannelTypes">Save channel types</button>
      <br/>
    </div>
  </div>
</template>

<script>
  module.exports = {
    data: ()=>{
      return {
        uptime_s: 0,
        build:'unknown',
        sys:'unknown',
        ip:'unknown',
        mac:'unknown',
        mqtthost:'unknown',
        mqtttopic:'unknown',
        shortName:'unknown',
        webapp:'unknown',
        chipset:'unknown',
        shortStartupCommand:'',
        flags:0,
        supportsClientDeviceDB: false,

        pins:{ rolenames:[], roles:[], channels:[] },
        channelTypes:{ typenames:[], types:[] },
        deviceFlag:"",
        deviceCommand: "",
        deviceTemplate: "",

        error:'',
        interval: null,

        releases: [],
        latest: "", // read from github
        latest_base: "", // numeric version extracted from latest
        currentversion: "", // extracted from build
        currentversion_base: "", // numeric version extracted from currentversion
        lateststr: "",

        peers:[],
      }
    },
    computed:{
      formattedUptime(){
        return this.formatUptime(this.uptime_s);
      }
    },
    methods:{
      getinfo(){
        let url = window.device+'/api/info';
        fetch(url)
            .then(response => response.json())
            .then(res => {
                this.uptime_s   = res.uptime_s;
                this.build      = res.build;
                this.sys        = res.sys;
                this.ip         = res.ip;
                this.mac        = res.mac;
                this.mqtthost   = res.mqtthost;
                this.mqtttopic  = res.mqtttopic;
                this.shortName  = res.shortName;
                this.webapp     = res.webapp;
                this.chipset    = res.chipset;
                this.flags      = res.flags;
                this.shortStartupCommand = res.startcmd;
                this.supportsClientDeviceDB = res.supportsClientDeviceDB;

                this.currentversion = this.build.split(' ').pop();
                this.currentversion_base = this.extractBaseVersion(this.currentversion);
                // only get releases the first time.
                if (!this.releases.length){
                  this.getReleases();
                }
                //Only if chip supplied supports SSDP=true or did not supply it at all (backward compatibility)
                if (res.supportsSSDP === undefined || res.supportsSSDP === 1){
                  this.getPeers();
                }
				this.refreshTemplate();
            })
            .catch(err => {
              this.error = err.toString();
              console.error(err)
            }); // Never forget the final catch!

      },

      getPeers(){
        let url = window.device+'/obkdevicelist';
        fetch(url)
          .then(response => response.json())
          .then(res => {
            this.peers = [];
            for (let i = 0; i < res.length; i++){
              let peer = { url:'http://'+res[i].ip, name:res[i].ip };
              this.peers.push(peer);
            }
          });
      },
	  refreshTemplate() {
		const device = {
		  vendor: 'Tuya',
		  bDetailed: '0',
		  name: 'Full Device Name Here',
		  model: 'enter short model name here',
		  chip: 'BK7231T',
		  board: 'TODO',
      flags: 0,
		  keywords : [
				"TODO",
				"TODO",
				"TODO"
			  ],
		  pins : {
			  },
      command: "",
		  image: 'https://obrazki.elektroda.pl/YOUR_IMAGE.jpg',
		  wiki: 'https://www.elektroda.com/rtvforum/topic_YOUR_TOPIC.html',
		};
    device.command = this.shortStartupCommand;
    device.flags = this.flags;
		device.chip = this.chipset;
		//device.pins = 
    for (let i = 0; i < this.pins.roles.length; i++){
			if(this.pins.roles[i] == 0)
			{
				continue;
			}
			if(this.pins.roles[i] == undefined)
			{
				continue;
			}
			let rName = this.pins.rolenames[this.pins.roles[i]];
			let ch1 = 0;
      if(this.pins.channels && i < this.pins.channels.length)
      {
          ch1 = this.pins.channels[i];
      }
			//let obj = { "5", "Relay;1" };
			device.pins[i] = rName+";"+ch1;
      if(this.pins.channels2 && i < this.pins.channels2.length)
      {
			  let ch2 = this.pins.channels2[i];
        device.pins[i] += ";"+ch2;
      }
    }
		deviceTemplate = JSON.stringify(device, null, 2);
		// fix for not working textArea for me?
		this.deviceTemplateElement.value = deviceTemplate;
	  },
      getPins(){
        let url = window.device+'/api/pins';
        fetch(url)
            .then(response => response.json())
            .then(res => {
              this.pins = res;
			  this.refreshTemplate();
            })
            .catch(err => {
              this.error = err.toString();
              console.error(err)
            }); // Never forget the final catch!

      },
      getChannelTypes(){
        let url = window.device+'/api/channelTypes';
        fetch(url)
            .then(response => response.json())
            .then(res => {
              this.channelTypes = res;
			  this.refreshTemplate();
            })
            .catch(err => {
              this.error = err.toString();
              console.error(err)
            }); // Never forget the final catch!

      },
      savePins() {
        let tosave = {};

        //Send more data pieces conditionally to prevent errors
        if (this.supportsClientDeviceDB) {
          //Valid deviceFlag is >=0 and <=10 (see new_pins.h)
          if (this.deviceFlag){ //Check flag value if populated
            var deviceFlagParsed = parseInt(this.deviceFlag, 10);
            if (!isFinite(deviceFlagParsed) || isNaN(deviceFlagParsed) || (deviceFlagParsed < 0) || (deviceFlagParsed > 10)){
              alert("Invalid flag value. Valid values are integers >= 0 and <= 10");
              return;
            }
          }

          tosave.deviceFlag = deviceFlagParsed;

          //Only send non-empty string value
          var deviceCommandParsed = (this.deviceCommand || "").trim();
          if (deviceCommandParsed){
            tosave.deviceCommand = deviceCommandParsed;
          }
        }

        for (let i = 0; i < this.pins.channels.length; i++){
          this.pins.channels[i] = +this.pins.channels[i];
        }
        for (let i = 0; i < this.pins.roles.length; i++){
          this.pins.roles[i] = +this.pins.roles[i];
        }
        tosave.channels = this.pins.channels;
        tosave.roles = this.pins.roles;

        let url = window.device+'/api/pins';
        fetch(url, {
                method: 'POST',
                body: JSON.stringify(tosave),
            })
            .then(response => response.json())
            .then(res => {
              this.error = JSON.stringify(res);
            })
            .catch(err => {
              this.error = err.toString();
              console.error(err)
            }); // Never forget the final catch!

        console.log('would save',this.pins);
      },
      saveChannelTypes() {
        let tosave = {};

        for (let i = 0; i < this.channelTypes.types.length; i++){
          this.channelTypes.types[i] = +this.channelTypes.types[i];
        }
        tosave.types = this.channelTypes.types;

        let url = window.device+'/api/channelTypes';
        fetch(url, {
                method: 'POST',
                body: JSON.stringify(tosave),
            })
            .then(response => response.json())
            .then(res => {
              this.error = JSON.stringify(res);
            })
            .catch(err => {
              this.error = err.toString();
              console.error(err)
            }); // Never forget the final catch!

        console.log('would save',this.channelTypes);
      },
      getTemplateAsFile() {  
        let baseName = "Unnamed";
        if(this.shortName != undefined && this.shortName.length > 0) {
          baseName = this.shortName;
        } else {
          baseName = this.mqtttopic;
        }
        let text = this.deviceTemplateElement.value;
        let timestamp = new Date().toLocaleString().replace(/[:/]/g, '-');
        timestamp = timestamp.replace(", ","_");
        const filename = `${baseName}_${timestamp}.json`;
        const blob = new Blob([text], { type: 'text/plain' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.setAttribute('download', filename);
        a.setAttribute('href', url);
        a.click();
        URL.revokeObjectURL(url);
      },
      getTemplateAsClipboard() {
        this.deviceTemplateElement.select();
        document.execCommand('copy');
        this.deviceTemplateElement.blur();
      },
      extractBaseVersion(input){
        if (input === undefined || input === null) return "";
        const s = String(input);

        // Extract the first dotted numeric sequence (e.g. 1.18.245) from:
        // "1.18.245_hlw8112", "v1.18.245", "Release 1.18.245", etc.
        const m = s.match(/(\d+(?:\.\d+){1,4})/);
        return m ? m[1] : "";
      },
      compareVersions(a, b){
        const pa = String(a).split('.').map(x => parseInt(x, 10));
        const pb = String(b).split('.').map(x => parseInt(x, 10));

        const len = Math.max(pa.length, pb.length);
        for (let i = 0; i < len; i++){
          const av = (pa[i] || 0);
          const bv = (pb[i] || 0);
          if (av > bv) return 1;
          if (av < bv) return -1;
        }
        return 0;
      },
      getReleases(){
        let base = "https://api.github.com/repos/openshwprojects/OpenBK7231T_App/releases";
        fetch(base)
          .then(response => response.json())
          .then(data => {

            // If GitHub returns an error object (rate limit, etc.), do not break the UI
            if (!Array.isArray(data) || !data.length){
              this.lateststr = "";
              return;
            }

            this.releases = data;

            const rel = data.find(r => r && !r.draft && !r.prerelease) || data[0];

            this.latest = rel.name || "";
            this.latest_base = this.extractBaseVersion(this.latest);

            this.lateststr = "";

            if (this.latest_base && this.currentversion_base){
              if (this.compareVersions(this.latest_base, this.currentversion_base) > 0){
                this.lateststr = `(<a href="${rel.html_url}" target="_blank" rel="noopener noreferrer">${this.latest_base}</a> available)`;
              }
              return;
            }

            // Fallback to old behaviour if we couldn't extract versions
            if (this.latest && this.latest !== this.currentversion){
              this.lateststr = `(<a href="${rel.html_url}" target="_blank" rel="noopener noreferrer">${this.latest}</a> available)`;
            }
          })
          .catch(err => {
              this.error = err.toString();
              console.error(err)
            });
      },
      formatUptime(totalSeconds){
        let s = Math.max(0, Math.floor(Number(totalSeconds) || 0));

        // Note: months/years are approximate (30-day months, 365-day years)
        const units = [
          ["year",   365 * 24 * 3600],
          ["month",   30 * 24 * 3600],
          ["week",     7 * 24 * 3600],
          ["day",          24 * 3600],
          ["hour",             3600],
          ["minute",             60],
          ["second",              1],
        ];

        const parts = [];
        for (const [name, size] of units) {
          const value = Math.floor(s / size);
          s -= value * size;

          // Omit zero units, but always show seconds if nothing else is present
          if (value === 0 && !(name === "second" && parts.length === 0)) continue;

          parts.push(`${value} ${name}${value === 1 ? "" : "s"}`);
        }

        return parts.join(", ");
      }
    },
    mounted (){
        this.msg = 'fred';
        console.log('mounted controller');
		    this.deviceTemplateElement = document.getElementById("deviceTemplate");
        this.getPins();
        this.getChannelTypes();
        this.getinfo();
        this.interval = setInterval(()=>{
          this.getinfo();
        }, 10000);
    },
    destroyed(){
      clearInterval(this.interval);
    }

  }
//@ sourceURL=/vue/info.vue
</script>

<style scoped>
  .container {
    display: flex;
    justify-content: center;
  }

  .item {
    padding: 0 15px;
  }
  .pin-index {
    display: inline-block;
    width: 20px;
  }
</style>
