<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Base para todos os models do domínio: chave primária UUID.
 */
abstract class BaseModel extends Model
{
    use HasUuids;
}
