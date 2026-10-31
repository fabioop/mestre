import { Composition } from "remotion";
import { Demo, totalFrames } from "./Demo";
import { DemoV1_1, totalFramesV1_1 } from "./DemoV1_1";
import { DemoV2, totalFramesV2 } from "./DemoV2";
import { README_CLIP_HEIGHT, README_CLIP_WIDTH, ReadmeClip, readmeClipFrames } from "./ReadmeClip";

export const Root = () => (
  <>
    <Composition id="Demo" component={Demo} durationInFrames={totalFrames} fps={30} width={1920} height={1080} />
    <Composition id="DemoV1-1" component={DemoV1_1} durationInFrames={totalFramesV1_1} fps={30} width={1920} height={1080} />
    <Composition id="DemoV2" component={DemoV2} durationInFrames={totalFramesV2} fps={30} width={1920} height={1080} />
    <Composition id="ReadmeClip" component={ReadmeClip} durationInFrames={readmeClipFrames} fps={30} width={README_CLIP_WIDTH} height={README_CLIP_HEIGHT} />
  </>
);
