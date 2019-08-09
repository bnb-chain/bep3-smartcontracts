module.exports = {
  compilers: {
    solc: {
      version: "0.5.8",
    }
  },
  networks: {
    test: {
      host: "127.0.0.1",
      port: 8545,
      network_id: "5555"
    }
  },
};
