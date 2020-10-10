import 'aisdecode.dart';
import 'cpa.dart';
import 'package:nmea/nmea.dart';

/// Core AIS handler class used to connect to an NMEA0183 source and
/// decode messages therefrom.
///
/// Override `they(PCS them, int mmsi)`
/// to implement your own AIS handler.
///
/// `they(them, mmsi)` will be invoked any time a (complete) VDM sentence is
/// received.
///
/// This will attempt to reconnect if a connection is dropped see
/// [NMEASocketReader] for details.
///
/// This class maintains a (non-persistent) cache of the most recent message
/// of each type received, keyed by MMSI useful for doing things like name
/// lookup and drilldown to full AIS data should you need to.
abstract class AISHandler {
  String _lastMsg;
  String _payload = '';
  /*final String host;
  final int port;*/

  final NMEAReader _nmea;

  /// Create a handler reading from host:port
  AISHandler(String host, int port) : _nmea = NMEASocketReader(host, port);
  AISHandler.using(this._nmea);

  // switch source/restart??


  // Start running
  void run() => _nmea.process(_handleNMEA);

  /// Change the host and port number; will disconnect and reconnect to a new source.
  void setSource(final String host, final int port) {
    if (_nmea is NMEASocketReader) {
      (_nmea as NMEASocketReader).hostname = host;
      (_nmea as NMEASocketReader).port = port;
    }
  }

  // The underlying NMEA reader
  NMEAReader get nmea => _nmea;

  /// [they] will be invoked each time an AIS target is reported
  ///
  /// [them] is the [PCS] of the target
  ///
  /// [mmsi] is the MMSI of the target.
  void they(final PCS them, final int mmsi);

  // Map of MMSI to Type to most recently received VDM
  Map<int,Map<int,AIS>> _static = Map();

  /// Most recent message of given [type] from [mmsi]
  ///
  /// If no message has been received, or this MMSI is unknown, then returns null
  AIS getMostRecentMessage(final int mmsi, final int msgType) => _static[mmsi]??[msgType];

  // Most recent messages of each type for given mmsi
  Map<int, AIS> getMostRecentMessages(final int mmsi) => Map.unmodifiable(_static[mmsi]);

  // stash the message by MMSI and Type
  void _stash(final int mmsi, final int type, final AIS ais) {
    _static.putIfAbsent(mmsi, ()=>new Map<int,AIS>())[type] = ais;
  }

  // receiver for NMEA messges
  void _handleNMEA(var msg) {
    // Here's the meat:
    if (msg is VDM) {
      // NMEA process has already unpacked the message; the interesting bit is in [payload].
      // Accumulate the payload until [fragment] == [fragments]
      // as VDMs can span multiple NMEA sentences
      _payload += msg.payload;
      if (msg.fragment == msg.fragments) {
        // this is the last message in the chain
        final AIS ais = AIS.from(_payload);

        if (ais is Type5) {
          nameFor(ais.mmsi, ais.shipname);
          _stash(ais.mmsi, 5, ais);

        } else if (ais is Type24A) {
          nameFor(ais.mmsi, ais.shipname);
          _stash(ais.mmsi, 0x24A, ais);

        } else if (ais is Type18) {
          _stash(ais.mmsi, 0x18, ais);
          if (ais.course != null) {
            PCS them = PCS(ais.lat / 60, ais.lon / 60, ais.course, ais.speed);
            they(them, ais.mmsi);
          }

        } else if (ais is CNB) {
          _stash(ais.mmsi, ais.type, ais);
          // Type 1, 2, 3 extend CNB:
          if (ais.course != null) {
            PCS them = PCS(ais.lat / 60, ais.lon / 60, ais.course, ais.sog);
            they(them, ais.mmsi);
          }
        } else if (ais is Type24B) {
          _stash(ais.mmsi, 0x24B, ais);
          // do something else?

        } else if (ais is Type21) {
          // static stuff: buoys, lanbys etc
          nameFor(ais.mmsi, ais.name);
          _stash(ais.mmsi, 21, ais);

          PCS them = PCS(ais.lat / 60, ais.lon / 60, 0, 0);
          they(them, ais.mmsi);

        } else {
          // print("not handled: $ais");

        }

        _lastMsg = null;
        _payload = '';
      } else if (_lastMsg != null && _lastMsg != msg.msgID) {
        // unexpected - out of sequence?

      } else {
        _lastMsg = msg.msgID;
      }
    }
  }

  /// Override this method if you want to be advised of name updates.
  void nameFor(int mmsi, String shipname) {}
}