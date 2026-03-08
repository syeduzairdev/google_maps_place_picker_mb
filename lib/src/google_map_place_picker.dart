import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:geolocator/geolocator.dart';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_place_picker_mb/google_maps_place_picker.dart';
import 'package:google_maps_place_picker_mb/providers/place_provider.dart';
import 'package:google_maps_place_picker_mb/src/components/animated_pin.dart';
import 'package:flutter_google_maps_webservices/geocoding.dart';
import 'package:flutter_google_maps_webservices/places.dart';
import 'package:provider/provider.dart';
import 'package:tuple/tuple.dart';

typedef SelectedPlaceWidgetBuilder = Widget Function(
  BuildContext context,
  PickResult? selectedPlace,
  SearchingState state,
  bool isSearchBarFocused,
);

typedef PinBuilder = Widget Function(
  BuildContext context,
  PinState state,
);

class GoogleMapPlacePicker extends StatelessWidget {
  const GoogleMapPlacePicker({
    super.key,
    required this.initialTarget,
    required this.appBarKey,
    this.selectedPlaceWidgetBuilder,
    this.pinBuilder,
    this.onSearchFailed,
    this.onMoveStart,
    this.onMapCreated,
    this.debounceMilliseconds,
    this.enableMapTypeButton,
    this.enableMyLocationButton,
    this.onToggleMapType,
    this.onMyLocation,
    this.onPlacePicked,
    this.usePinPointingSearch,
    this.usePlaceDetailSearch,
    this.selectInitialPosition,
    this.language,
    this.pickArea,
    this.forceSearchOnZoomChanged,
    this.hidePlaceDetailsWhenDraggingPin,
    this.onCameraMoveStarted,
    this.onCameraMove,
    this.onCameraIdle,
    this.selectText,
    this.outsideOfPickAreaText,
    this.zoomGesturesEnabled = true,
    this.zoomControlsEnabled = false,
    this.fullMotion = false,
  });

  final LatLng initialTarget;
  final GlobalKey appBarKey;

  final SelectedPlaceWidgetBuilder? selectedPlaceWidgetBuilder;
  final PinBuilder? pinBuilder;

  final ValueChanged<String>? onSearchFailed;
  final VoidCallback? onMoveStart;
  final MapCreatedCallback? onMapCreated;
  final VoidCallback? onToggleMapType;
  final VoidCallback? onMyLocation;
  final ValueChanged<PickResult>? onPlacePicked;

  final int? debounceMilliseconds;
  final bool? enableMapTypeButton;
  final bool? enableMyLocationButton;

  final bool? usePinPointingSearch;
  final bool? usePlaceDetailSearch;

  final bool? selectInitialPosition;

  final String? language;
  final CircleArea? pickArea;

  final bool? forceSearchOnZoomChanged;
  final bool? hidePlaceDetailsWhenDraggingPin;

  /// GoogleMap pass-through events:
  final Function(PlaceProvider)? onCameraMoveStarted;
  final CameraPositionCallback? onCameraMove;
  final Function(PlaceProvider)? onCameraIdle;

  // strings
  final String? selectText;
  final String? outsideOfPickAreaText;

  /// Zoom feature toggle
  final bool zoomGesturesEnabled;
  final bool zoomControlsEnabled;

  /// Use never scrollable scroll-view with maximum dimensions to prevent unnecessary re-rendering.
  final bool fullMotion;

  Future<void> _searchByCameraLocation(PlaceProvider provider) async {
    // We don't want to search location again if camera location is changed by zooming in/out.
    if (forceSearchOnZoomChanged == false &&
        provider.prevCameraPosition != null &&
        provider.prevCameraPosition!.target.latitude ==
            provider.cameraPosition!.target.latitude &&
        provider.prevCameraPosition!.target.longitude ==
            provider.cameraPosition!.target.longitude) {
      provider.placeSearchingState = SearchingState.Idle;
      return;
    }

    if (provider.cameraPosition == null) {
      provider.placeSearchingState = SearchingState.Idle;
      return;
    }

    provider.placeSearchingState = SearchingState.Searching;

    final GeocodingResponse response =
        await provider.geocoding.searchByLocation(
      Location(
          lat: provider.cameraPosition!.target.latitude,
          lng: provider.cameraPosition!.target.longitude),
      language: language,
    );

    if (response.errorMessage?.isNotEmpty == true ||
        response.status == "REQUEST_DENIED") {
      debugPrint("Camera Location Search Error: ${response.errorMessage}");
      onSearchFailed?.call(response.status);
      provider.placeSearchingState = SearchingState.Idle;
      return;
    }

    if (usePlaceDetailSearch!) {
      final PlacesDetailsResponse detailResponse =
          await provider.places.getDetailsByPlaceId(
        response.results[0].placeId,
        language: language,
      );

      if (detailResponse.errorMessage?.isNotEmpty == true ||
          detailResponse.status == "REQUEST_DENIED") {
        debugPrint(
            "Fetching details by placeId Error: ${detailResponse.errorMessage}");
        onSearchFailed?.call(detailResponse.status);
        provider.placeSearchingState = SearchingState.Idle;
        return;
      }

      provider.selectedPlace =
          PickResult.fromPlaceDetailResult(detailResponse.result);
    } else {
      provider.selectedPlace =
          PickResult.fromGeocodingResult(response.results[0]);
    }

    provider.placeSearchingState = SearchingState.Idle;
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Stack(
      children: <Widget>[
        if (fullMotion)
          SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: SizedBox(
                  width: mediaQuery.size.width,
                  height: mediaQuery.size.height,
                  child: Stack(
                    alignment: AlignmentDirectional.center,
                    children: [
                      _buildGoogleMap(context),
                      _buildPin(),
                    ],
                  ))),
        if (!fullMotion) ...[_buildGoogleMap(context), _buildPin()],
        _buildFloatingCard(),
        _buildMapIcons(context),
        _buildZoomButtons()
      ],
    );
  }

  Widget _buildGoogleMapInner(PlaceProvider provider, MapType mapType) {
    final initialCameraPosition =
        CameraPosition(target: initialTarget, zoom: 15);
    return GoogleMap(
      zoomGesturesEnabled: zoomGesturesEnabled,
      zoomControlsEnabled: false,
      myLocationButtonEnabled: false,
      compassEnabled: false,
      mapToolbarEnabled: false,
      initialCameraPosition: initialCameraPosition,
      mapType: mapType,
      myLocationEnabled: true,
      circles: pickArea != null && pickArea!.radius > 0
          ? {pickArea!}
          : const <Circle>{},
      onMapCreated: (GoogleMapController controller) {
        provider.mapController = controller;
        provider.setCameraPosition(null);
        provider.pinState = PinState.Idle;

        // When select initialPosition set to true.
        if (selectInitialPosition!) {
          provider.setCameraPosition(initialCameraPosition);
          _searchByCameraLocation(provider);
        }
        onMapCreated?.call(controller);
      },
      onCameraIdle: () {
        if (provider.isAutoCompleteSearching) {
          provider.isAutoCompleteSearching = false;
          provider.pinState = PinState.Idle;
          provider.placeSearchingState = SearchingState.Idle;
          return;
        }
        // Perform search only if the setting is to true.
        if (usePinPointingSearch!) {
          // Search current camera location only if camera has moved (dragged) before.
          if (provider.pinState == PinState.Dragging) {
            // Cancel previous timer.
            if (provider.debounceTimer?.isActive ?? false) {
              provider.debounceTimer!.cancel();
            }
            provider.debounceTimer =
                Timer(Duration(milliseconds: debounceMilliseconds!), () {
              _searchByCameraLocation(provider);
            });
          }
        }
        provider.pinState = PinState.Idle;
        onCameraIdle?.call(provider);
      },
      onCameraMoveStarted: () {
        onCameraMoveStarted?.call(provider);
        provider.setPrevCameraPosition(provider.cameraPosition);
        // Cancel any other timer.
        provider.debounceTimer?.cancel();
        // Update state, dismiss keyboard and clear text.
        provider.pinState = PinState.Dragging;
        // Begins the search state if the hide details is enabled
        if (hidePlaceDetailsWhenDraggingPin!) {
          provider.placeSearchingState = SearchingState.Searching;
        }
        onMoveStart!();
      },
      onCameraMove: (CameraPosition position) {
        provider.setCameraPosition(position);
        onCameraMove?.call(position);
      },
      // gestureRecognizers make it possible to navigate the map when it's a
      // child in a scroll view e.g ListView, SingleChildScrollView...
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
      },
    );
  }

  Widget _buildGoogleMap(BuildContext context) {
    return Selector<PlaceProvider, MapType>(
        selector: (_, provider) => provider.mapType,
        builder: (_, data, cachedChild) => _buildGoogleMapInner(
            PlaceProvider.of(context, listen: false), data));
  }

  Widget _buildPin() {
    return Selector<PlaceProvider, PinState>(
      selector: (_, provider) => provider.pinState,
      builder: (context, state, cachedChild) {
        if (pinBuilder == null) {
          return _defaultPinBuilder(context, state);
        } else {
          return Center(
            child: Builder(
                builder: (builderContext) =>
                    pinBuilder!(builderContext, state)),
          );
        }
      },
    );
  }

  Widget _defaultPinBuilder(BuildContext context, PinState state) {
    if (state == PinState.Preparing) {
      return const SizedBox.shrink();
    }
    Widget pinIcon = const Icon(Icons.place, size: 36, color: Colors.red);
    if (state == PinState.Dragging) {
      pinIcon = AnimatedPin(child: pinIcon);
    }
    // Align the tip of the pin to the center using Transform
    return Center(
      child: Transform.translate(
        offset: const Offset(0, -18), // Move up by half the icon height (36/2)
        child: pinIcon,
      ),
    );
  }

  Widget _buildFloatingCard() {
    return Selector<PlaceProvider,
        Tuple4<PickResult?, SearchingState, bool, PinState>>(
      selector: (_, provider) => Tuple4(
          provider.selectedPlace,
          provider.placeSearchingState,
          provider.isSearchBarFocused,
          provider.pinState),
      builder: (context, data, cachedChild) {
        if ((data.item1 == null && data.item2 == SearchingState.Idle) ||
            data.item3 == true ||
            data.item4 == PinState.Dragging &&
                hidePlaceDetailsWhenDraggingPin!) {
          return const SizedBox.shrink();
        } else {
          if (selectedPlaceWidgetBuilder == null) {
            return _defaultPlaceWidgetBuilder(context, data.item1, data.item2);
          } else {
            return Builder(
                builder: (builderContext) => selectedPlaceWidgetBuilder!(
                    builderContext, data.item1, data.item2, data.item3));
          }
        }
      },
    );
  }

  Widget _buildZoomButtons() {
    return Selector<PlaceProvider, Tuple2<GoogleMapController?, LatLng?>>(
      selector: (_, provider) => Tuple2<GoogleMapController?, LatLng?>(
          provider.mapController, provider.cameraPosition?.target),
      builder: (context, data, cachedChild) {
        if (!zoomControlsEnabled ||
            data.item1 == null ||
            data.item2 == null) {
          return const SizedBox.shrink();
        }
        final size = MediaQuery.of(context).size;
        return Positioned(
          bottom: size.height * 0.1 - 3.6,
          right: 2,
          child: Card(
            elevation: 4.0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: SizedBox(
              width: size.width * 0.15 - 13,
              height: 107,
              child: Column(
                children: <Widget>[
                  IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () async {
                        double currentZoomLevel =
                            await data.item1!.getZoomLevel();
                        currentZoomLevel = currentZoomLevel + 2;
                        data.item1!.animateCamera(
                          CameraUpdate.newCameraPosition(
                            CameraPosition(
                              target: data.item2!,
                              zoom: currentZoomLevel,
                            ),
                          ),
                        );
                      }),
                  const SizedBox(height: 2),
                  IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: () async {
                        double currentZoomLevel =
                            await data.item1!.getZoomLevel();
                        currentZoomLevel = currentZoomLevel - 2;
                        if (currentZoomLevel < 0) currentZoomLevel = 0;
                        data.item1!.animateCamera(
                          CameraUpdate.newCameraPosition(
                            CameraPosition(
                              target: data.item2!,
                              zoom: currentZoomLevel,
                            ),
                          ),
                        );
                      }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _defaultPlaceWidgetBuilder(
      BuildContext context, PickResult? data, SearchingState state) {
    final size = MediaQuery.of(context).size;
    return FloatingCard(
      bottomPosition: size.height * 0.1,
      leftPosition: size.width * 0.15,
      rightPosition: size.width * 0.15,
      width: size.width * 0.7,
      borderRadius: BorderRadius.circular(12.0),
      elevation: 4.0,
      color: Theme.of(context).cardColor,
      child: state == SearchingState.Searching
          ? _buildLoadingIndicator()
          : _buildSelectionDetails(context, data!),
    );
  }

  Widget _buildLoadingIndicator() {
    return const SizedBox(
      height: 48,
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }

  Widget _buildSelectionDetails(BuildContext context, PickResult result) {
    final canBePicked = pickArea == null ||
        pickArea!.radius <= 0 ||
        Geolocator.distanceBetween(
                pickArea!.center.latitude,
                pickArea!.center.longitude,
                result.geometry!.location.lat,
                result.geometry!.location.lng) <=
            pickArea!.radius;
    final buttonColor = WidgetStateColor.resolveWith(
        (states) => canBePicked ? Colors.lightGreen : Colors.red);
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: <Widget>[
          Text(
            result.formattedAddress!,
            style: const TextStyle(fontSize: 18),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          (canBePicked && (selectText?.isEmpty ?? true)) ||
                  (!canBePicked && (outsideOfPickAreaText?.isEmpty ?? true))
              ? SizedBox.fromSize(
                  size: const Size(56, 56),
                  child: ClipOval(
                    child: Material(
                      child: InkWell(
                          overlayColor: buttonColor,
                          onTap: () {
                            if (canBePicked) {
                              onPlacePicked!(result);
                            }
                          },
                          child: Icon(
                              canBePicked
                                  ? Icons.check_sharp
                                  : Icons.app_blocking_sharp,
                              color: buttonColor)),
                    ),
                  ),
                )
              : SizedBox.fromSize(
                  size: Size(MediaQuery.of(context).size.width * 0.8, 56),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10.0),
                    child: Material(
                      child: InkWell(
                          overlayColor: buttonColor,
                          onTap: () {
                            if (canBePicked) {
                              onPlacePicked!(result);
                            }
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                  canBePicked
                                      ? Icons.check_sharp
                                      : Icons.app_blocking_sharp,
                                  color: buttonColor),
                              const SizedBox(width: 10),
                              Text(
                                  canBePicked
                                      ? selectText!
                                      : outsideOfPickAreaText!,
                                  style: TextStyle(color: buttonColor))
                            ],
                          )),
                    ),
                  ),
                )
        ],
      ),
    );
  }

  Widget _buildMapIcons(BuildContext context) {
    if (appBarKey.currentContext == null) {
      return const SizedBox.shrink();
    }
    final RenderBox appBarRenderBox =
        appBarKey.currentContext!.findRenderObject() as RenderBox;
    return Positioned(
      top: appBarRenderBox.size.height,
      right: 15,
      child: Column(
        children: <Widget>[
          if (enableMapTypeButton!)
            SizedBox(
              width: 35,
              height: 35,
              child: RawMaterialButton(
                shape: const CircleBorder(),
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.black54
                    : Colors.white,
                elevation: 4.0,
                onPressed: onToggleMapType,
                child: const Icon(Icons.layers),
              ),
            ),
          const SizedBox(height: 10),
          if (enableMyLocationButton!)
            SizedBox(
              width: 35,
              height: 35,
              child: RawMaterialButton(
                shape: const CircleBorder(),
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.black54
                    : Colors.white,
                elevation: 4.0,
                onPressed: onMyLocation,
                child: const Icon(Icons.my_location),
              ),
            ),
        ],
      ),
    );
  }
}
