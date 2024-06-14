/*
 * Copyright 2024 LiveKit
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#if swift(>=5.9)
internal import LiveKitWebRTC
#else
@_implementationOnly import LiveKitWebRTC
#endif

protocol EngineDelegate: AnyObject {
    func engine(_ engine: Engine, didMutateState state: Engine.State, oldState: Engine.State) async
    func engine(_ engine: Engine, didUpdateSpeakers speakers: [Livekit_SpeakerInfo]) async
    func engine(_ engine: Engine, didAddTrack track: LKRTCMediaStreamTrack, rtpReceiver: LKRTCRtpReceiver, stream: LKRTCMediaStream) async
    func engine(_ engine: Engine, didRemoveTrack track: LKRTCMediaStreamTrack) async
    func engine(_ engine: Engine, didReceiveUserPacket packet: Livekit_UserPacket) async
}
