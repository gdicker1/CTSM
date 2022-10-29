"""
This module includes the definition and functions for defining a Mesh type. 
"""

import logging
import datetime
import numpy as np
import xarray as xr
import pandas as pd
import dask.array as da
import dask.dataframe as dd
from dask.diagnostics import ProgressBar

logger = logging.getLogger(__name__)

class MeshType:
    """
    An object for describing mesh or grid files.
    """

    def __init__(self, center_lats, center_lons, mesh_name=None, mask=None):
        """
        Construct a mesh object

        center_lats :
            latitudes (either 1D or 2D)
        center_lons :
            longitudes (either 1D or 2D)
        mesh_name : str or None, optional
            Name of the mesh
        mask : np array or None
            numpy array that include landmask
        """

        self.mesh_name = mesh_name
        self.center_lats = center_lats
        self.center_lons = center_lons

        # -- dims of lat and lon (1d or 2d)
        self.lat_dims = len(self.center_lats.dims)
        self.lon_dims = len(self.center_lons.dims)
        self.check_lat_lon_dims()

        if mask is None:
            self.create_artificial_mask()
        else:
            self.mask = mask

    def __str__(self):
        """
        Converts ingredients of this class to string for printing.
        """
        return "{}\n{}".format(
            str(self.__class__),
            "\n".join(
                (
                    "{} = {}".format(str(key), str(self.__dict__[key]))
                    for key in sorted(self.__dict__)
                )
            ),
        )

    def check_lat_lon_dims(self):
        """
        Check latitude and longitude dimensions to make sure they are either 1 or 2.
        """
        if self.lat_dims not in [1, 2]:
            print(
                "Unrecognized grid! The dimension of latitude should be either 1 or 2 but it is {}.".format(
                    self.lat_dims
                )
            )
        if self.lon_dims not in [1, 2]:
            print(
                "Unrecognized grid! The dimension of longitude should be either 1 or 2 but it is {}.".format(
                    self.lon_dims
                )
            )

    def create_artificial_mask(self):
        logger.info("Creating an artificial mask for this region...")

        if self.lat_dims == 1:
            # -- 1D mask (lat x lon)
            lats_size = self.center_lats.size
            lons_size = self.center_lons.size
            mask = np.ones([lons_size, lats_size], dtype=np.int8)
        elif self.lat_dims == 2:
            # -- 2D mask
            mask = np.ones(
                center_lats.shape, dtype=np.int8
            )  # np.ones(tuple(self.center_lats.sizes.values()), dtype=np.int8)  #
        mask_da = da.from_array(mask)
        self.mask = mask_da

    def create_2d_coords(self):
        """
        Create 2d center points for our mesh
        and convert them to Dask Array.
        """
        self.center_lats = self.center_lats.astype(np.float64, copy=False)
        self.center_lons = self.center_lons.astype(np.float64, copy=False)

        if self.lat_dims == 1:
            # -- 1D lats and lons
            lats_size = self.center_lats.size
            lons_size = self.center_lons.size

            # -- convert center points from 1d to 2d
            self.center_lat2d = da.broadcast_to(
                self.center_lats.values[None, :], (lons_size, lats_size)
            )
            self.center_lon2d = da.broadcast_to(
                self.center_lons.values[:, None], (lons_size, lats_size)
            )
        elif self.lat_dims == 2:
            # -- 2D lats and lons
            dims = self.center_lons.shape

            # -- convert 2D lats and lons to number x and y
            lons_size = dims[0]
            lats_size = dims[1]

            # -- convert to dask array
            self.center_lat2d = da.from_array(self.center_lats)
            self.center_lon2d = da.from_array(self.center_lons)

    def calculate_corners(self, unit="degrees"):
        """
        calculate corner coordinates by averaging adjacent cells

        Parameters
        ----------
        unit : {'degrees', 'radians'}, optional
            The unit of corner coordinates.
        """

        self.create_2d_coords()
        # -- pad center_lats for calculating edge gridpoints
        # -- otherwise we cannot calculate the corner coords
        # -- for the edge rows/columns.

        padded_lat2d = da.from_array(
            np.pad(
                self.center_lat2d.compute(), (1, 1), mode="reflect", reflect_type="odd"
            )
        )

        # -- pad center_lons for calculating edge grids
        padded_lon2d = da.from_array(
            np.pad(
                self.center_lon2d.compute(), (1, 1), mode="reflect", reflect_type="odd"
            )
        )

        # -- calculate corner lats for each grid
        north_east = (
            padded_lat2d[1:-1, 1:-1]
            + padded_lat2d[0:-2, 1:-1]
            + padded_lat2d[1:-1, 2:]
            + padded_lat2d[0:-2, 2:]
        ) / 4.0
        north_west = (
            padded_lat2d[1:-1, 1:-1]
            + padded_lat2d[0:-2, 1:-1]
            + padded_lat2d[1:-1, 0:-2]
            + padded_lat2d[0:-2, 0:-2]
        ) / 4.0
        south_west = (
            padded_lat2d[1:-1, 1:-1]
            + padded_lat2d[1:-1, 0:-2]
            + padded_lat2d[2:, 1:-1]
            + padded_lat2d[2:, 0:-2]
        ) / 4.0
        south_east = (
            padded_lat2d[1:-1, 1:-1]
            + padded_lat2d[1:-1, 2:]
            + padded_lat2d[2:, 1:-1]
            + padded_lat2d[2:, 2:]
        ) / 4.0

        # -- order counter-clockwise
        self.corner_lats = da.stack(
            [
                north_west.T.reshape((-1,)).T,
                south_west.T.reshape((-1,)).T,
                south_east.T.reshape((-1,)).T,
                north_east.T.reshape((-1,)).T,
            ],
            axis=1,
        )

        # -- calculate corner lons for each grid
        north_east = (
            padded_lon2d[1:-1, 1:-1]
            + padded_lon2d[0:-2, 1:-1]
            + padded_lon2d[1:-1, 2:]
            + padded_lon2d[0:-2, 2:]
        ) / 4.0
        north_west = (
            padded_lon2d[1:-1, 1:-1]
            + padded_lon2d[0:-2, 1:-1]
            + padded_lon2d[1:-1, 0:-2]
            + padded_lon2d[0:-2, 0:-2]
        ) / 4.0
        south_west = (
            padded_lon2d[1:-1, 1:-1]
            + padded_lon2d[1:-1, 0:-2]
            + padded_lon2d[2:, 1:-1]
            + padded_lon2d[2:, 0:-2]
        ) / 4.0
        south_east = (
            padded_lon2d[1:-1, 1:-1]
            + padded_lon2d[1:-1, 2:]
            + padded_lon2d[2:, 1:-1]
            + padded_lon2d[2:, 2:]
        ) / 4.0

        # -- order counter-clockwise
        self.corner_lons = da.stack(
            [
                north_west.T.reshape((-1,)).T,
                south_west.T.reshape((-1,)).T,
                south_east.T.reshape((-1,)).T,
                north_east.T.reshape((-1,)).T,
            ],
            axis=1,
        )
        self.unit = unit

    def calculate_node_coords(self):
        """
        Calculates coordinates of each node (for 'nodeCoords' in ESMF mesh).
        In ESMF mesh, 'nodeCoords' is a two-dimensional array with dimension ('nodeCount','coordDim')
        """
        # -- create an array of corner pairs
        corner_pairs = da.stack(
            [self.corner_lons.T.reshape((-1,)).T, self.corner_lats.T.reshape((-1,)).T],
            axis=1,
        )

        # -- remove coordinates that are shared between the elements
        node_coords = dd.from_dask_array(corner_pairs).drop_duplicates().values
        node_coords.compute_chunk_sizes()
        # -- check size of unique coordinate pairs
        dims = self.mask.shape
        nlon = dims[0]
        nlat = dims[1]
        elem_conn_size = nlon * nlat + nlon + nlat + 1
        self.node_coords = node_coords

        if self.node_coords.shape[0] != elem_conn_size:
            logger.warning(
                "The size of unique coordinate pairs is {} but expected size is {}!".format(
                    self.node_coords.shape[0], elem_conn_size
                )
            )
            sys.exit(2)

    def calculate_elem_conn(self):
        """
        Calculate element connectivity (for 'elementConn' in ESMF mesh).
        In ESMF mesh, 'elementConn' describes how the nodes are connected together.
        """
        corners = dd.concat(
            [
                dd.from_dask_array(corner)
                for corner in [
                    self.corner_lons.T.reshape((-1,)).T,
                    self.corner_lats.T.reshape((-1,)).T,
                ]
            ],
            axis=1,
        )
        corners.columns = ["lon", "lat"]

        elem_conn = corners.compute().groupby(["lon", "lat"], sort=False).ngroup() + 1
        elem_conn = da.from_array(elem_conn.to_numpy())
        # -- reshape to write to ESMF
        self.elem_conn = elem_conn.T.reshape((4, -1)).T

    def create_esmf(self, mesh_fname, area=None):
        """
        Create an ESMF mesh file for the mesh

        Parameters
        ----------
        mesh_fname : str
            The path to write the ESMF meshfile

        area : numpy.ndarray or None
            Array containing element areas for the ESMF mesh file
            If None, ESMF calculates element areas internally.
        """
        # -- calculate node coordinates
        self.calculate_node_coords()

        # -- calculate element connections
        self.calculate_elem_conn()

        center_coords = da.stack(
            [
                self.center_lon2d.T.reshape((-1,)).T,
                self.center_lat2d.T.reshape((-1,)).T,
            ],
            axis=1,
        )
        # create output Xarray dataset
        ds_out = xr.Dataset()

        ds_out["origGridDims"] = xr.DataArray(
            np.array(self.center_lon2d.shape, dtype=np.int32), dims=("origGridRank")
        )
        ds_out["nodeCoords"] = xr.DataArray(
            self.node_coords, dims=("nodeCount", "coordDim"), attrs={"units": self.unit}
        )
        ds_out["elementConn"] = xr.DataArray(
            self.elem_conn,
            dims=("elementCount", "maxNodePElement"),
            attrs={
                "long_name": "Node indices that define the element connectivity",
                "_FillValue": -1,
            },
        )
        ds_out.elementConn.encoding = {"dtype": np.int32}

        ds_out["numElementConn"] = xr.DataArray(
            4 * np.ones(self.center_lon2d.size, dtype=np.int32),
            dims=("elementCount"),
            attrs={"long_name": "Number of nodes per element"},
        )
        ds_out["centerCoords"] = xr.DataArray(
            center_coords, dims=("elementCount", "coordDim"), attrs={"units": self.unit}
        )

        # -- add mask
        ds_out["elementMask"] = xr.DataArray(
            self.mask.T.reshape((-1,)).T,
            dims=("elementCount"),
            attrs={"units": "unitless", "_FillValue": -9999.0},
        )
        ds_out.elementMask.encoding = {"dtype": np.int32}

        # -- add area if provided
        if area:
            ds_out["elementArea"] = xr.DataArray(
                area.T.reshape((-1,)).T,
                dims=("elementCount"),
                attrs={"units": "radians^2", "long_name": "area weights"},
            )

        # -- force no '_FillValue' if not specified (default Nan)
        for var in ds_out.variables:
            if "_FillValue" not in ds_out[var].encoding:
                ds_out[var].encoding["_FillValue"] = None

        # -- add global attributes
        ds_out.attrs["title"] = "ESMF unstructured grid file"
        ds_out.attrs["gridType"] = "unstructured mesh"
        ds_out.attrs["version"] = "0.9"
        ds_out.attrs["conventions"] = "ESMFMESH"
        ds_out.attrs["date_created"] = datetime.datetime.now().strftime(
            "%Y-%m-%d %H:%M:%S"
        )

        # -- write Xarray dataset to file
        if mesh_fname is not None:
            logger.info("Writing ESMF Mesh file to : %s", mesh_fname)
            ds_out.to_netcdf(mesh_fname)
            logger.info("Successfully created ESMF Mesh file : %s", mesh_fname)
