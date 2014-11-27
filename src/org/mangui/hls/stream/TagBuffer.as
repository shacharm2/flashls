/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.stream {
    import org.mangui.hls.utils.Log;

    import flash.events.TimerEvent;
    import flash.events.Event;
    import flash.utils.Timer;

    import org.mangui.hls.HLS;
    import org.mangui.hls.flv.FLVTag;

    /*
     * intermediate FLV Tag Buffer
     *  input : FLV tags retrieved from different fragment loaders (video/alt-audio...)
     *  output : provide muxed FLV tags to HLSNetStream
     */
    public class TagBuffer {
        private var _hls : HLS;
        /** Timer used to process FLV tags. **/
        private var _timer : Timer;
        private var _audioTags : Vector.<FLVData>;
        private var _videoTags : Vector.<FLVData>;
        private var _metaTags : Vector.<FLVData>;

        public function TagBuffer(hls : HLS) {
            _hls = hls;
            flushAll();
            _timer = new Timer(100, 0);
            _timer.addEventListener(TimerEvent.TIMER, _checkBuffer);
            _timer.start();
        }

        public function flushAll() : void {
            _audioTags = new Vector.<FLVData>();
            _videoTags = new Vector.<FLVData>();
            _metaTags = new Vector.<FLVData>();
        }

        public function flushAudio() : void {
            _audioTags = new Vector.<FLVData>();
        }

        public function appendTags(tags : Vector.<FLVTag>, min_pts : Number, max_pts : Number, continuity : int, start_position : Number) : void {
            for each (var tag : FLVTag in tags) {
                var position : Number = start_position + (tag.pts - min_pts) / 1000;
                var tagData : FLVData = new FLVData(tag, position, continuity);
                switch(tag.type) {
                    case FLVTag.AAC_HEADER:
                    case FLVTag.AAC_RAW:
                    case FLVTag.MP3_RAW:
                        _audioTags.push(tagData);
                        break;
                    case FLVTag.AVC_HEADER:
                    case FLVTag.AVC_NALU:
                        _videoTags.push(tagData);
                        break;
                    case FLVTag.DISCONTINUITY:
                    case FLVTag.METADATA:
                        _metaTags.push(tagData);
                        break;
                    default:
                }
            }
            _timer.start();
        }

        /**  Timer **/
        private function _checkBuffer(e : Event) : void {
            // check netstream buffer len
            var tags : Vector.<FLVTag> = new Vector.<FLVTag>();
            var min_pts : Number;
            var max_pts : Number;
            var start_position : Number;
            var continuity : int;

            var flvdata : FLVData;
            while ((flvdata = shift()) != null) {
                tags.push(flvdata.tag);
                if (isNaN(start_position)) {
                    start_position = flvdata.position;
                    continuity = flvdata.continuity;
                }
            }
            if (tags.length) {
                min_pts = tags[0].pts;
                max_pts = tags[tags.length - 1].pts;
                (_hls.stream as HLSNetStream).appendTags(tags, min_pts, max_pts, continuity, start_position);
                Log.debug("appending " + tags.length + " tags");
            }
        }

        /*
         * 
         * return next tag from queue, using the following priority :
         * smallest continuity
         * then smallest pts
         * then metadata then video then audio tags
         */
        private function shift() : FLVData {
            if (_videoTags.length == 0 && _audioTags.length == 0 && _metaTags.length == 0)
                return null;

            var continuity : int = int.MAX_VALUE;
            // find smallest continuity counter
            if (_metaTags.length) continuity = Math.min(continuity, _metaTags[0].continuity);
            if (_videoTags.length) continuity = Math.min(continuity, _videoTags[0].continuity);
            if (_audioTags.length) continuity = Math.min(continuity, _audioTags[0].continuity);

            var pts : Number = Number.MAX_VALUE;
            // for this continuity counter, find smallest PTS
            if (_metaTags.length && _metaTags[0].continuity == continuity) pts = Math.min(pts, _metaTags[0].tag.pts);
            if (_videoTags.length && _videoTags[0].continuity == continuity) pts = Math.min(pts, _videoTags[0].tag.pts);
            if (_audioTags.length && _audioTags[0].continuity == continuity) pts = Math.min(pts, _audioTags[0].tag.pts);

            // for this continuity counter, this PTS, prioritize tags with the following order : metadata/video/audio
            if (_metaTags.length && _metaTags[0].continuity == continuity && _metaTags[0].tag.pts == pts) return _metaTags.shift();
            if (_videoTags.length && _videoTags[0].continuity == continuity && _videoTags[0].tag.pts == pts) return _videoTags.shift();
            else return _audioTags.shift();
        }

        public function dispose() : void {
            _hls = null;
            _timer.stop();
            _timer = null;
        }
    }
}

import org.mangui.hls.flv.FLVTag;


class FLVData {
    public var tag : FLVTag;
    public var position : Number;
    public var continuity : int;

    public function FLVData(tag : FLVTag, position : Number, continuity : int) {
        this.tag = tag;
        this.position = position;
        this.continuity = continuity;
    }
}
