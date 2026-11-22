<template>
    <div>
      <p><a v-bind:href="nativeurl" target="_blank">Native UI on this device {{nativeurl}}</a></p>
      <p>A simple web app to go with OpenBekenIOT equipped devices by <a href="https://github.com/btsimonh">btsimonh</a></p>
      <p>This app is a pure javascript application written in VueJS as an SFC .vue component, and dynamically loaded from the device via a simple webpage.  The intent here is to be able to provide a rich UI and allow the device UI to remain simple (and small).</p>
      <p>Currently, it supports displaying logging from the device</p>
    </div>
</template>

<script>
  module.exports = {
    props: ['nativeurl'],
  }
//@ sourceURL=/vue/about.vue
</script>
