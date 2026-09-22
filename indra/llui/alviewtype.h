/**
 * @file alviewtype.h
 * @brief SKOOMA-PORT: stand-in for Alchemy's ALViewType. Our LLView has no
 *        per-class type table, so AL_VIEW_TYPE declares nothing and
 *        ALViewType::as<T>() is a dynamic_cast.
 *
 * $LicenseInfo:firstyear=2026&license=viewerlgpl$
 * Alchemy Viewer Source Code
 * Copyright (C) 2026, Rye <rye@alchemyviewer.org>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation;
 * version 2.1 of the License only.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * $/LicenseInfo$
 */

#ifndef AL_ALVIEWTYPE_H
#define AL_ALVIEWTYPE_H

#define AL_VIEW_TYPE(Class, Base)

struct ALViewType
{
    template <class T, class V> static T* as(V* view) { return dynamic_cast<T*>(view); }
    template <class T, class V> static const T* as(const V* view) { return dynamic_cast<const T*>(view); }
};

#endif // AL_ALVIEWTYPE_H
