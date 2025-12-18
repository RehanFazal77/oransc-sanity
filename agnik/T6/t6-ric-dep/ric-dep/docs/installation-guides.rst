.. This work is licensed under a Creative Commons Attribution 4.0 International License.
.. SPDX-License-Identifier: CC-BY-4.0
.. ===============LICENSE_START=======================================================
.. Copyright (C) 2019-2020 AT&T Intellectual Property
.. ===================================================================================
.. This documentation file is distributed under the Creative Commons Attribution
.. 4.0 International License (the "License"); you may not use this file except in
.. compliance with the License.  You may obtain a copy of the License at
..
.. http://creativecommons.org/licenses/by/4.0
..
.. This file is distributed on an "AS IS" BASIS,
.. WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
.. See the License for the specific language governing permissions and
.. limitations under the License.
.. ===============LICENSE_END=========================================================

===================
Installation Guides
===================

This document describes how to install the RIC components deployed by scripts and Helm charts
under the ric-plt/dep repository, including the dependencies and required system resources.

.. contents::
   :depth: 3
   :local:

Version history
===============

+--------------------+--------------------+--------------------+--------------------+
| **Date**           | **Ver.**           | **Author**         | **Comment**        |
|                    |                    |                    |                    |
+--------------------+--------------------+--------------------+--------------------+
| 2020-02-29         | 0.1.0              | Abdulwahid W       |                    |
| 2025-12-15         | 0.2.0              | Agnik Misra        |                    |
+--------------------+--------------------+--------------------+--------------------+


Overview
========

This section explains the installation of Near Realtime RAN Intelligent Controller Platform only.

Prerequisites
=============

The steps below assume a clean installation of Ubuntu 20.04 (no k8s, no docker, no helm)

Installing Near Realtime RIC in RIC Cluster
===========================================

After the Kubernetes cluster is installed, the next step is to install the (Near Realtime) RIC Platform.

.. include:: ./deployment_guide.rst

Installing RIC-APPs
===================

RIC Applications
----------------

.. include:: installation-xapps.rst

Optional Installations
======================

OPTIONALLY use Redis Cluster (instead of Redis standalone)
----------------------------------------------------------

.. include:: installation-rediscluster.rst


Appendix
========

.. include:: ./platform_requirements.rst

.. include:: ./recipe_selection.rst

.. include:: ./image_overrides.rst
