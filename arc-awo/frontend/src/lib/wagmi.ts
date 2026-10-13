import { http, createConfig } from "wagmi";
import { arcMainnet, arcTestnet } from "./chains";

const defaultChain =
  process.env.NEXT_PUBLIC_DEFAULT_CHAIN === "mainnet" ? arcMainnet : arcTestnet;

export const wagmiConfig = createConfig({
  chains: [defaultChain, defaultChain.id === arcMainnet.id ? arcTestnet : arcMainnet],
  transports: {
    [arcMainnet.id]: http(),
    [arcTestnet.id]: http(),
  },
  ssr: true,
});

export const isTestnetDefault = defaultChain.id === arcTestnet.id;
