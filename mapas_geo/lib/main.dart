import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Localizador de Puntos',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const LocalizadorPage(),
    );
  }
}

class LocalizadorPage extends StatefulWidget {
  const LocalizadorPage({super.key});

  @override
  State<LocalizadorPage> createState() => _LocalizadorPageState();
}

class _LocalizadorPageState extends State<LocalizadorPage> {
  static const LatLng _posicionInicial = LatLng(20.2756, -97.9611);

  GoogleMapController? _mapController;
  StreamSubscription<Position>? _positionSubscription;
  Position? _posicionUsuario;
  LatLng? _destino;
  Set<Marker> _marcadores = <Marker>{};
  double? _distanciaMetros;
  String _direccion = 'Toca el mapa para elegir un destino';
  bool _permisoUbicacionConcedido = false;
  int _solicitudDireccion = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(obtenerUbicacion());
    });
  }

  // Comprueba permisos y servicios antes de solicitar la posición inicial.
  Future<void> obtenerUbicacion() async {
    try {
      final servicioHabilitado = await Geolocator.isLocationServiceEnabled();
      if (!mounted) return;
      if (!servicioHabilitado) {
        _mostrarMensaje('Activa el GPS para obtener tu ubicación.');
        return;
      }

      var permiso = await Geolocator.checkPermission();
      if (!mounted) return;
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
        if (!mounted) return;
      }
      if (permiso == LocationPermission.deniedForever) {
        _mostrarMensaje(
          'El permiso de ubicación está denegado permanentemente. '
          'Actívalo en la configuración de la aplicación.',
        );
        return;
      }
      if (permiso != LocationPermission.whileInUse &&
          permiso != LocationPermission.always) {
        _mostrarMensaje('No se concedió el permiso de ubicación.');
        return;
      }

      setState(() {
        _permisoUbicacionConcedido = true;
      });

      final posicion = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;

      setState(() {
        _posicionUsuario = posicion;
        _distanciaMetros = _calcularDistancia(posicion, _destino);
      });
      unawaited(_centrarEnPosicion(posicion));
      _iniciarSeguimiento();
    } catch (error) {
      debugPrint('Error al obtener la ubicación: $error');
      if (!mounted) return;
      _mostrarMensaje('No se pudo obtener la ubicación actual.');
    }
  }

  // Mantiene la posición y la distancia actualizadas mientras el usuario se mueve.
  void _iniciarSeguimiento() {
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(
      _actualizarPosicion,
      onError: (Object error) {
        debugPrint('Error al seguir la ubicación: $error');
        if (!mounted) return;
        _mostrarMensaje('No se pudo actualizar la ubicación.');
      },
    );
  }

  void _actualizarPosicion(Position posicion) {
    if (!mounted) return;
    setState(() {
      _posicionUsuario = posicion;
      _distanciaMetros = _calcularDistancia(posicion, _destino);
    });
  }

  double? _calcularDistancia(Position? posicion, LatLng? destino) {
    if (posicion == null || destino == null) return null;
    return Geolocator.distanceBetween(
      posicion.latitude,
      posicion.longitude,
      destino.latitude,
      destino.longitude,
    );
  }

  // Sustituye el destino anterior y actualiza su dirección al terminar geocoding.
  Future<void> _agregarMarcador(LatLng destino) async {
    final solicitud = ++_solicitudDireccion;
    if (!mounted) return;

    setState(() {
      _destino = destino;
      _direccion = 'Buscando dirección...';
      _distanciaMetros = _calcularDistancia(_posicionUsuario, destino);
      _marcadores = <Marker>{
        _crearMarcador(destino, _direccion),
      };
    });

    try {
      final lugares = await placemarkFromCoordinates(
        destino.latitude,
        destino.longitude,
      );
      if (!mounted || solicitud != _solicitudDireccion) return;

      final direccion = _formatearDireccion(lugares);
      _actualizarDireccionDelMarcador(destino, direccion);
    } catch (error) {
      debugPrint('Error al obtener la dirección: $error');
      if (!mounted || solicitud != _solicitudDireccion) return;
      _actualizarDireccionDelMarcador(
        destino,
        'Dirección no disponible',
      );
    }
  }

  String _formatearDireccion(List<Placemark> lugares) {
    if (lugares.isEmpty) return 'Dirección no disponible';

    final lugar = lugares.first;
    final calle = lugar.street?.trim();
    final colonia = lugar.subLocality?.trim();
    final partes = <String>[
      if (calle != null && calle.isNotEmpty) calle,
      if (colonia != null && colonia.isNotEmpty) colonia,
    ];
    return partes.isEmpty ? 'Dirección no disponible' : partes.join(', ');
  }

  void _actualizarDireccionDelMarcador(LatLng destino, String direccion) {
    if (!mounted) return;
    setState(() {
      _direccion = direccion;
      _marcadores = <Marker>{
        _crearMarcador(destino, direccion),
      };
    });
  }

  Marker _crearMarcador(LatLng destino, String direccion) {
    return Marker(
      markerId: const MarkerId('destino'),
      position: destino,
      infoWindow: InfoWindow(title: 'Destino', snippet: direccion),
    );
  }

  Future<void> _centrarEnPosicion(Position posicion) async {
    final controller = _mapController;
    if (controller == null) return;
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(posicion.latitude, posicion.longitude),
          zoom: 16,
        ),
      ),
    );
  }

  void _mostrarMensaje(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  void dispose() {
    unawaited(_positionSubscription?.cancel());
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Localizador de Puntos')),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: _posicionInicial,
              zoom: 15.5,
            ),
            myLocationEnabled: _permisoUbicacionConcedido,
            myLocationButtonEnabled: _permisoUbicacionConcedido,
            markers: _marcadores,
            onMapCreated: (controller) {
              _mapController = controller;
              final posicion = _posicionUsuario;
              if (posicion != null) {
                unawaited(_centrarEnPosicion(posicion));
              }
            },
            onTap: (destino) {
              unawaited(_agregarMarcador(destino));
            },
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              top: false,
              child: Card(
                elevation: 5,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DatoUbicacion(
                        icono: Icons.my_location,
                        etiqueta: 'Ubicación actual',
                        valor: _posicionUsuario == null
                            ? 'Obteniendo ubicación...'
                            : '${_posicionUsuario!.latitude.toStringAsFixed(5)}, '
                                '${_posicionUsuario!.longitude.toStringAsFixed(5)}',
                      ),
                      const SizedBox(height: 12),
                      _DatoUbicacion(
                        icono: Icons.straighten,
                        etiqueta: 'Distancia al destino',
                        valor: _distanciaMetros == null
                            ? '—'
                            : '${_distanciaMetros!.toStringAsFixed(0)} m',
                      ),
                      const SizedBox(height: 12),
                      _DatoUbicacion(
                        icono: Icons.place_outlined,
                        etiqueta: 'Dirección',
                        valor: _direccion,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DatoUbicacion extends StatelessWidget {
  const _DatoUbicacion({
    required this.icono,
    required this.etiqueta,
    required this.valor,
  });

  final IconData icono;
  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                etiqueta,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Text(valor),
            ],
          ),
        ),
      ],
    );
  }
}
