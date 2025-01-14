// Copyright 2021 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

using System.Text;

namespace Tizen.Flutter.Embedding
{
    /// <summary>
    /// <see cref="IMessageCodec{T}" /> for UTF-8 encoded String messages.
    /// </summary>
    public class StringCodec : IMessageCodec<string>
    {
        /// <InheritDoc/>
        public byte[] EncodeMessage(string message)
        {
            if (message == null)
            {
                return null;
            }
            return Encoding.UTF8.GetBytes(message);
        }

        /// <InheritDoc/>
        public string DecodeMessage(byte[] message)
        {
            if (message == null)
            {
                return null;
            }
            return Encoding.UTF8.GetString(message);
        }
    }
}
